# claude-wire

When the user picks "Yes" on the Claude-wire question (the default), the skill generates two files: `CLAUDE.md` at the project root and `.claude/settings.json`.

---

## `.claude/settings.json` (every type)

Allowlists the common safe commands so Claude Code doesn't prompt on every tool use.

```json
{
  "permissions": {
    "allow": [
      "Bash(docker:*)",
      "Bash(docker compose:*)",
      "Bash(git:*)",
      "Bash(ls:*)",
      "Bash(cat:*)",
      "Bash(grep:*)",
      "Bash(rg:*)",
      "Bash(find:*)",
      "Bash(pwd)",
      "Bash(tree)"
    ]
  }
}
```

`yarn` and `node` are **deliberately omitted** — the convention is to run them only inside Docker. If a user adds `Bash(yarn:*)` to this allowlist, they're violating the Docker-first contract documented in CLAUDE.md.

---

## `CLAUDE.md` — base template (~55 lines)

```markdown
# {{name}}

{{stack-one-liner}}

## How to run anything

**Always use Docker. Never run `yarn`, `node`, or `npm` on the host.**

```
docker compose up                                  # dev server
docker compose run --rm app yarn lint              # lint
docker compose run --rm app yarn test              # tests
docker compose run --rm app yarn build             # production build
docker compose run --rm app yarn up <package>      # add or upgrade a dep
```

The Dockerfile pins Yarn 4 and Node 20. The host doesn't need either.

## TypeScript / ESM rules

- `"type": "module"` is set; this is an ESM project.
- TS imports need a `.js` suffix even though the source is `.ts`:
  ```ts
  import { foo } from './foo.js';   // correct
  import { foo } from './foo';      // wrong — fails at runtime
  ```
- `tsconfig.json` uses `"module": "NodeNext"` (backend) / `"module": "ESNext"` (frontend).

## Where things go

- **New {{module-noun}}** → `src/modules/<name>/` with the {{module-file-set}}.
- **Shared building blocks** → `src/shared/{components,hooks,lib}/`. Never put shared code inside a module.
{{ if auth }}- **Auth** → pages in `src/modules/auth/`; the layer (context, middleware, hooks, types, adapters) in `src/shared/auth/`. **Never import an adapter directly from a module** — always use `useAuth()` (frontend) or `requireAuth` (backend).{{ /if }}
{{ if db }}- **DB** → pool in `src/shared/db/client.ts`. Modules call `query()`; they don't construct connections.{{ /if }}
- **Tests** → `tests/` mirroring `src/`. Vitest only — no Jest.

## Env vars

- Validated by zod in `src/config/env.ts`. Add a new key there and to `.env.example` at the same time.
- `.env` is gitignored. Never commit secrets.

{{ db-paragraph }}

{{ auth-paragraph }}

## Do not

- Run `yarn install` on the host. Use `docker compose build`.
- Switch to CommonJS. The project is ESM end-to-end.
- Add Prisma / Drizzle / Knex. The default driver is `mysql2` (or `pg` / `better-sqlite3`); raw SQL queries via `src/shared/db/client.ts`.
- Introduce a second test runner. Vitest covers backend, CLI, library, and frontend.
{{ if auth }}- Import auth adapters directly from modules. Go through `useAuth()` or `requireAuth`.{{ /if }}
- Add husky / lint-staged / commitlint without discussing first.

## Adding a new {{module-noun}}

1. `mkdir src/modules/<name>`
2. Generate the {{module-file-set}} inside it.
3. {{ if frontend }}Register the lazy export in `src/routes/index.tsx`.{{ /if }}{{ if backend }}Export `{ router, mountPath }` from `index.ts` — `src/app.ts` auto-mounts it.{{ /if }}
4. Add `tests/modules/<name>/` mirroring the source.
```

---

## Per-type fill-ins for the placeholders

### Backend API

- `{{stack-one-liner}}`: `Node 20 · Yarn 4 · TypeScript (ESM) · Express`
- `{{module-noun}}`: `module`
- `{{module-file-set}}` (depends on architecture):
  - Modular monolith: `<name>.routes.ts, <name>.controller.ts, <name>.service.ts, <name>.schema.ts, index.ts`
  - Layered: see [architecture-styles.md](architecture-styles.md#2-layered)
  - Clean: see [architecture-styles.md](architecture-styles.md#3-clean-architecture)
  - Hexagonal: see [architecture-styles.md](architecture-styles.md#4-hexagonal-ports--adapters)
- `{{ if frontend }}` block: deleted
- `{{ if backend }}` block: kept
- `{{ db-paragraph }}` (only if DB chosen):
  ```
  ## Database
  - MySQL 8 is in the `db` service. Connection pool lives in `src/shared/db/client.ts`.
  - Modules call `query(sql, params)` — no per-request connection.
  - The `/health` endpoint deliberately does NOT ping the DB. Add a separate `/ready` if you want a DB-aware probe.
  ```
- `{{ auth-paragraph }}` (only if auth chosen): see Auth fill-ins below.

### CLI / job

- `{{stack-one-liner}}`: `Node 20 · Yarn 4 · TypeScript (ESM) · Commander`
- `{{module-noun}}`: `command`
- `{{module-file-set}}`: `<name>.ts` (one file under `src/commands/`)
- `{{ if backend }}` and `{{ if frontend }}`: both deleted
- The "Adding a new …" section becomes:
  ```
  1. Create `src/commands/<name>.ts` exporting a function.
  2. Wire it into `src/index.ts` with `program.command('<name>').action(...)`.
  3. Add `tests/commands/<name>.test.ts`.
  ```

### Frontend React

- `{{stack-one-liner}}`: `Node 20 · Yarn 4 · TypeScript (ESM) · Vite · React`
- `{{module-noun}}`: `page module`
- `{{module-file-set}}`: `<Name>Page.tsx, index.ts` (plus optional `components/`, `hooks/`)
- `{{ if frontend }}` block: kept
- `{{ if backend }}` block: deleted
- `{{ db-paragraph }}`: deleted (frontend has no DB)
- Add a "Lazy-loading" paragraph:
  ```
  ## Lazy-loading

  Every page module's `index.ts` does:
  ```ts
  import { lazy } from 'react';
  export default lazy(() => import('./HomePage'));
  ```
  Pages are loaded on-demand. `src/routes/index.tsx` wraps everything in `<Suspense>`.
  ```

### Fullstack

- `{{stack-one-liner}}`: `Node 20 · Yarn 4 · TypeScript (ESM) · Express + Vite · Yarn 4 workspaces`
- Document workspace commands:
  ```
  ## Workspace commands

  - `docker compose up` — boots api + web + db together.
  - `docker compose run --rm api yarn test` — just the API.
  - `docker compose run --rm web yarn test` — just the web.
  - Cross-workspace: `docker compose -f docker-compose.tools.yml run --rm tools yarn workspaces foreach -A run lint`.
  ```
- Mention `packages/shared/`: "Cross-stack types live in `packages/shared/src/index.ts`. Both `apps/api` and `apps/web` import from there — keep the public surface small."

### Monorepo

- `{{stack-one-liner}}`: `Node 20 · Yarn 4 · TypeScript (ESM) · Yarn 4 workspaces`
- Replace "Where things go" with:
  ```
  ## Layout

  - `apps/<name>/` — runnable apps (use the project-starter skill again to add one).
  - `packages/<name>/` — reusable libraries.
  - `tools/` — internal scripts and dev tools.

  Yarn 4 workspaces with `nmHoistingLimits: workspaces` — siblings don't see each other's deps unless they declare them.
  ```

### Library

- `{{stack-one-liner}}`: `Node 20 · Yarn 4 · TypeScript (ESM) · published as a package`
- Replace the "How to run anything" block with:
  ```
  docker compose run --rm app yarn build    # produces dist/
  docker compose run --rm app yarn test
  docker compose run --rm app yarn lint
  ```
  No `docker compose up`.
- Add a "Publishing" section:
  ```
  ## Publishing

  - Bump the version in `package.json`.
  - Tag the commit: `git tag v0.1.1 && git push --tags`.
  - GitHub Actions (`release.yml`) builds, tests, and runs `yarn npm publish`.
  - NPM_AUTH_TOKEN must be set as a repo secret.
  ```

---

## Auth-paragraph fill-ins

When auth is on, the `{{ auth-paragraph }}` placeholder is replaced with one of these:

### JWT

```
## Auth (JWT)

- Access tokens live in memory (frontend) and are signed with `JWT_SECRET` (backend).
- Refresh token is an httpOnly cookie, scoped to `/auth/refresh`.
- The layer is in `src/shared/auth/`. The adapter is `src/shared/auth/adapters/jwt.adapter.ts` — the only file that knows it's JWT.
- To swap auth methods, follow the "How to swap" section in `references/auth-layer.md` of the project-starter skill.
```

### Session

```
## Auth (cookie session)

- Sessions are stored server-side (default: in-memory; swap to Redis for production — see `express-session` docs).
- Cookie is httpOnly + sameSite=lax + secure-in-prod.
- The layer is in `src/shared/auth/`. The adapter is `src/shared/auth/adapters/session.adapter.ts`.
- To swap auth methods, follow the "How to swap" section in `references/auth-layer.md` of the project-starter skill.
```

### OAuth stub

```
## Auth (OAuth — stub)

- The OAuth adapter is a stub. You're expected to plug in a provider (Auth0 / Keycloak / GitHub / etc.).
- TODOs are marked in `src/shared/auth/adapters/oauth.adapter.ts`.
- The layer (context, middleware, hooks, types) is fully wired — only the adapter needs the provider-specific code.
```

---

## Length sanity check

After substitution, `CLAUDE.md` should be 50–70 lines. If it overshoots:

- Cut the "Do not" list to the four most relevant items for the type.
- Drop `{{ db-paragraph }}` if there's no DB.
- Drop `{{ auth-paragraph }}` if there's no auth.

If it undershoots (≤ 30 lines):
- Reinstate the cut sections.
- The user picked "skeleton only" hello-world — CLAUDE.md can be tighter because there's less to document. Don't pad.
