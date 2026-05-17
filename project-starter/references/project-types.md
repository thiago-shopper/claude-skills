# project-types

Per-type folder trees and stack matrices. The trees here are the **canonical layouts**; per-file bodies live in [file-templates.md](file-templates.md). Architecture-specific module layouts live in [architecture-styles.md](architecture-styles.md). Auth-layer additions live in [auth-layer.md](auth-layer.md). Database additions live in [database-recipes.md](database-recipes.md).

---

## Stack matrix

| Type           | Runtime           | Framework  | Test  | Build          | DB?     | Auth?   | Docker compose layout            |
| -------------- | ----------------- | ---------- | ----- | -------------- | ------- | ------- | -------------------------------- |
| Backend API    | Node 20 (Alpine)  | Express    | Vitest| tsc            | optional| optional| app + db                         |
| CLI / job      | Node 20 (Alpine)  | —          | Vitest| tsc            | rare    | no      | app (no exposed ports by default)|
| Frontend React | Node 20 → nginx   | Vite/React | Vitest| vite build     | no      | optional| app (dev) / nginx (prod)         |
| Fullstack      | Node 20 (Alpine)  | Express+Vite| Vitest| tsc + vite     | yes     | optional| api + web + db                   |
| Monorepo       | Node 20 (Alpine)  | per-pkg    | Vitest| per-pkg        | per-pkg | per-pkg | tools (runs `yarn workspaces foreach`) |
| Library        | Node 20 (Alpine)  | —          | Vitest| tsc (declaration:true)| no | no  | app (test/build only)            |

---

## Backend API

Default architecture is **Modular monolith**. Other architectures (Layered, Clean, Hexagonal) rearrange the *inside* of `src/modules/<name>/` — see [architecture-styles.md](architecture-styles.md).

```
{{name}}/
├── .claude/
│   └── settings.json
├── .github/
│   └── workflows/
│       └── ci.yml
├── .yarn/
│   └── releases/
│       └── yarn-4.5.0.cjs
├── src/
│   ├── modules/
│   │   ├── health/
│   │   │   ├── health.routes.ts
│   │   │   ├── health.controller.ts
│   │   │   ├── health.service.ts
│   │   │   ├── health.schema.ts
│   │   │   └── index.ts
│   │   └── auth/                    # if auth=yes — see auth-layer.md
│   ├── shared/
│   │   ├── middleware/
│   │   │   ├── error.ts
│   │   │   └── logger.ts
│   │   ├── auth/                    # if auth=yes — see auth-layer.md
│   │   ├── db/
│   │   │   └── client.ts            # if DB chosen — see database-recipes.md
│   │   ├── lib/
│   │   │   └── .gitkeep
│   │   └── types/
│   │       └── .gitkeep
│   ├── config/
│   │   └── env.ts
│   ├── app.ts
│   └── index.ts
├── tests/
│   └── modules/
│       └── health.test.ts
├── .dockerignore
├── .editorconfig
├── .env.example
├── .eslintrc.cjs
├── .gitignore
├── .prettierrc
├── .yarnrc.yml
├── CLAUDE.md                        # if Claude-wire=yes
├── Dockerfile
├── docker-compose.yml
├── nginx.conf                       # NOT generated — backend has no nginx
├── openapi.yaml                     # if API-docs=yes
├── package.json
├── README.md
├── tsconfig.json
└── vitest.config.ts
```

(`nginx.conf` is listed above only to call out: **do not** generate it for backend types — it belongs to frontend.)

**`docker-compose.yml`** services: `app` (built from `Dockerfile`, ports 3000, env_file `.env`, depends_on `db`) and `db` if a DB was chosen.

---

## CLI / script / job

```
{{name}}/
├── .claude/settings.json
├── .github/workflows/ci.yml
├── .yarn/releases/yarn-4.5.0.cjs
├── bin/
│   └── cli.ts                       # shebang: #!/usr/bin/env node
├── src/
│   ├── commands/
│   │   └── hello.ts
│   ├── shared/
│   │   └── lib/
│   │       └── .gitkeep
│   └── index.ts                     # exported main(args)
├── tests/
│   └── commands/
│       └── hello.test.ts
├── .dockerignore
├── .editorconfig
├── .env.example
├── .eslintrc.cjs
├── .gitignore
├── .prettierrc
├── .yarnrc.yml
├── CLAUDE.md
├── Dockerfile
├── docker-compose.yml
├── package.json                     # has "bin" field
├── README.md
├── tsconfig.json
└── vitest.config.ts
```

**`docker-compose.yml`** services: just `app`. Comments in the file show how to add a `cron`/`worker` variant.

---

## Frontend React (module-per-page, lazy-loaded)

The Vite bootstrap (via the ephemeral container) generates the baseline; the skill then **replaces or overlays** the files marked `[overlay]` below. Anything not marked is what Vite produced and we keep as-is (or remove if marked `[remove]`).

```
{{name}}/
├── .claude/settings.json                                      [overlay]
├── .github/workflows/ci.yml                                   [overlay]
├── .yarn/releases/yarn-4.5.0.cjs                              [overlay]
├── public/                                                    [from Vite]
│   └── vite.svg
├── src/
│   ├── modules/                                               [overlay]
│   │   ├── home/
│   │   │   ├── HomePage.tsx
│   │   │   ├── components/.gitkeep
│   │   │   ├── hooks/.gitkeep
│   │   │   └── index.ts
│   │   ├── settings/
│   │   │   ├── SettingsPage.tsx
│   │   │   └── index.ts
│   │   └── auth/                                              # if auth=yes
│   ├── layouts/                                               [overlay]
│   │   ├── MainLayout.tsx
│   │   └── AuthLayout.tsx
│   ├── shared/                                                [overlay]
│   │   ├── components/
│   │   │   └── Button.tsx
│   │   ├── hooks/
│   │   │   └── useFetch.ts
│   │   ├── lib/
│   │   │   └── api.ts
│   │   └── auth/                                              # if auth=yes
│   ├── routes/                                                [overlay]
│   │   └── index.tsx
│   ├── styles/                                                [overlay]
│   │   └── index.css
│   ├── App.tsx                                                [overlay — replaces Vite's]
│   ├── main.tsx                                               [from Vite]
│   ├── App.css                                                [remove]
│   ├── index.css                                              [remove — replaced by styles/index.css]
│   └── assets/                                                [from Vite]
│       └── react.svg
├── tests/                                                     [overlay]
│   ├── setup.ts
│   └── modules/
│       └── home/HomePage.test.tsx
├── .dockerignore                                              [overlay]
├── .editorconfig                                              [overlay]
├── .env.example                                               [overlay]
├── .eslintrc.cjs                                              [overlay — replaces Vite's]
├── .gitignore                                                 [overlay — replaces Vite's, adds .yarn/* rules]
├── .prettierrc                                                [overlay]
├── .yarnrc.yml                                                [overlay]
├── CLAUDE.md                                                  [overlay]
├── Dockerfile                                                 [overlay]
├── docker-compose.yml                                         [overlay]
├── index.html                                                 [from Vite]
├── nginx.conf                                                 [overlay]
├── package.json                                               [overlay — merges with Vite's: adds Yarn 4 fields, vitest, prettier, eslint]
├── README.md                                                  [overlay — replaces Vite's]
├── tsconfig.json                                              [overlay — merges with Vite's: enforces strict, paths]
├── tsconfig.node.json                                         [from Vite]
├── vite.config.ts                                             [overlay — adds test config]
└── vitest.config.ts                                           [NOT generated — Vitest config is merged into vite.config.ts]
```

`vitest.config.ts` is *not* a separate file for frontend — Vitest reads `vite.config.ts` via the `test` field. We keep it merged.

**`docker-compose.yml`** services: `app` (builds the `dev` stage of the Dockerfile; mounts `.:/app` with an anonymous `/app/node_modules` volume; ports 5173).

---

## Fullstack

```
{{name}}/
├── .claude/settings.json
├── .github/workflows/ci.yml                  # matrix on apps + packages
├── .yarn/releases/yarn-4.5.0.cjs
├── apps/
│   ├── api/                                  # full Backend API tree (above) MINUS its own docker-compose.yml
│   └── web/                                  # full Frontend React tree (above) MINUS its own docker-compose.yml
├── packages/
│   └── shared/
│       ├── src/
│       │   └── index.ts                      # exports cross-stack types
│       ├── package.json
│       └── tsconfig.json
├── .dockerignore
├── .editorconfig
├── .env.example
├── .eslintrc.cjs                             # root config; apps extend it
├── .gitignore
├── .prettierrc
├── .yarnrc.yml                               # has nmHoistingLimits: workspaces
├── CLAUDE.md
├── Dockerfile.tools                          # for `yarn workspaces foreach`
├── docker-compose.yml                        # api + web + db at root
├── package.json                              # workspaces, private:true
├── README.md
└── tsconfig.base.json                        # apps/* and packages/* extend this
```

**`docker-compose.yml`** services: `api` (builds `apps/api/Dockerfile`), `web` (builds `apps/web/Dockerfile`), `db` (if DB chosen). Each app gets its own bind mount + anonymous `node_modules` volume.

`apps/api/` and `apps/web/` keep their own `Dockerfile`s. The root compose's `build.context` points at each app directory.

---

## Monorepo

```
{{name}}/
├── .claude/settings.json
├── .github/workflows/ci.yml
├── .yarn/releases/yarn-4.5.0.cjs
├── apps/
│   └── .gitkeep
├── packages/
│   └── {{name}}-core/                        # one starter package (uses the Library tree above)
├── tools/
│   └── .gitkeep
├── .dockerignore
├── .editorconfig
├── .eslintrc.cjs
├── .gitignore
├── .prettierrc
├── .yarnrc.yml                               # nmHoistingLimits: workspaces
├── CLAUDE.md
├── Dockerfile.tools
├── docker-compose.yml                        # one `tools` service that mounts the repo
├── package.json                              # workspaces, private:true
├── README.md
└── tsconfig.base.json
```

The single `tools` service in compose exists so the user can run `docker compose run --rm tools yarn workspaces foreach -A run lint` without polluting the host.

---

## Library / package

```
{{name}}/
├── .claude/settings.json
├── .github/
│   └── workflows/
│       ├── ci.yml
│       └── release.yml                       # if publish target = npm or private registry
├── .yarn/releases/yarn-4.5.0.cjs
├── src/
│   ├── index.ts                              # public API: `export { hello } from './lib/hello.js';`
│   └── lib/
│       └── hello.ts                          # exports `hello(name: string)`
├── tests/
│   └── index.test.ts
├── .dockerignore
├── .editorconfig
├── .eslintrc.cjs
├── .gitignore                                # also ignores dist/
├── .npmignore                                # publish-time ignores (tests, configs)
├── .prettierrc
├── .yarnrc.yml
├── CLAUDE.md
├── Dockerfile                                # single stage; test/build only
├── docker-compose.yml                        # single `app` service
├── package.json                              # main, types, exports, publishConfig
├── README.md
├── tsconfig.json                             # declaration:true, declarationMap:true, composite:true
└── vitest.config.ts
```

**`docker-compose.yml`** services: just `app`. No ports, no db. Used for `docker compose run --rm app yarn test`.

---

## When to pick which type

- **Backend API** — anything that responds to HTTP and isn't paired with a UI in this repo.
- **CLI / script / job** — anything invoked from a shell or a scheduler. Includes batch jobs, cron workers, one-off migration scripts.
- **Frontend React app** — UI-only. The user has (or will have) a separate backend, or talks directly to a third-party API.
- **Fullstack app** — UI + API maintained together, shipped together. One repo, one CI, shared types.
- **Monorepo** — multiple apps and/or libraries with their own lifecycles. Don't pick this just because you have two services — Fullstack is simpler.
- **Library / package** — code meant to be consumed by other projects. Generates declaration files and publish wiring.

If the user is unsure, ask which **first** thing they want to run. "An HTTP endpoint" → Backend API. "A web page" → Frontend. "Both, together" → Fullstack.
