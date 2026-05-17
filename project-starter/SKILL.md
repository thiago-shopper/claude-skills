---
name: project-starter
description: |
  Use this skill when the user wants to scaffold a brand-new software project
  from scratch. Trigger phrases: "start a new project", "scaffold a new API",
  "new React app", "create a fullstack project", "/project-starter". The
  skill runs a 2-round interview (project type + name + hello-world + Claude-
  wire, then a conditional round for architecture/CI/DB/auth/API-docs),
  recommends defaults aggressively, confirms a complete plan, and only then
  writes real files. Supports six types: Backend API, CLI/script/job,
  Frontend React, Fullstack, Monorepo, Library. Backend architecture is
  chosen per project (modular monolith default, plus layered / clean /
  hexagonal); frontend always uses module-per-page with lazy-loaded routes,
  two main layouts, and a shared/ folder (kdb-tech/kdb-tech-ui-inspired).
  Stack: Yarn 4 + Node 20 + TypeScript (ESM) + Express/Vite + Vitest +
  ESLint + Prettier + MySQL 8 + GitHub Actions. Docker-first by design:
  the skill never installs yarn/node on the host, and every scaffolded
  project is operable end-to-end through `docker compose` alone. Writes a
  CLAUDE.md and .claude/settings.json so the new project integrates with
  the user's other Claude Skills.
version: 0.1.0
allowed-tools: [Bash, Read, Write, Edit, AskUserQuestion]
argument-hint: <optional project name>
---

# project-starter

Generate a complete, working project scaffold from a two-round interview. The output is **runnable through Docker alone** — `docker compose build && docker compose run --rm app yarn test` must succeed on a machine that has *only* Docker installed (no Node, no Yarn).

The skill never runs `yarn`, `npm`, `node`, or `corepack` on the host. Every operation goes through `docker run` or `docker compose`.

---

## When to use

- The user says "start a new project", "new API", "scaffold a React app", "make a monorepo", "/project-starter".
- The user is in an empty directory or wants a new subdirectory.

## Do not invoke when

- The user is adding a feature to an **existing** codebase — that's a regular implementation task.
- The user wants only one specific file (a Dockerfile, a `tsconfig.json`) — write it directly instead.
- The user wants to migrate or refactor an existing project — that's not scaffolding.
- The user asks for a stack we don't support yet (Python, Go, Bun, pnpm) — say so and offer to write a one-off scaffold manually.

---

## Workflow

### Step 1 — Preflight (Docker only)

Run in parallel:
- `docker --version` — must succeed.
- `docker compose version` — must succeed (Compose v2 plugin form; not the legacy `docker-compose` binary).
- `docker info` — daemon must be running.
- `git --version` — present (else skip `git init` at the end).
- `pwd` and `ls -A` — capture parent dir state.

**Do NOT check** for `node`, `yarn`, `npm`, or `corepack`. By design, they aren't required. If any user prompt mentions installing them locally, push back and explain the Docker-first model.

If any Docker check fails, follow the edge cases in [references/edge-cases.md](references/edge-cases.md) (E3, E4, E5).

If the user passed `<project-name>` as a skill argument, remember it for Round 1.

### Step 2 — Round 1 interview

One `AskUserQuestion` call with four questions: project type, name, hello-world toggle, Claude-wire toggle. Exact payload in [references/interview-flow.md](references/interview-flow.md#round-1).

Validate the project name immediately after:
- kebab-case-able? Lowercase letters, digits, hyphens only. If not, propose a sanitized form and ask the user to confirm (edge case **E2**).
- Does `./{{name}}` already exist? If yes, see edge case **E1**.

### Step 3 — Round 2 interview (conditional)

Drop in only the questions that apply to the chosen project type. **Backend types split into 2a + 2b** because the question set hits the 4-question cap. All other types stay single-round.

| Type                                | Round 2a                                                                 | Round 2b                                |
| ----------------------------------- | ------------------------------------------------------------------------ | --------------------------------------- |
| Backend API / Fullstack / Monorepo  | Architecture · CI · Database · Auth                                       | API docs · **Confirm proceed**          |
| Frontend React                      | CI · Auth · **Confirm proceed**                                           | —                                       |
| CLI / script / job                  | CI · Database (default No) · **Confirm proceed**                          | —                                       |
| Library / package                   | CI · Publish target · **Confirm proceed**                                 | —                                       |

Exact payloads, including option labels and Recommended defaults, live in [references/interview-flow.md](references/interview-flow.md#round-2).

**Confirm proceed** is the final question in the last round of every flow. Options: **proceed** *(Recommended)* / **edit choices** (re-run Round 2) / **cancel**.

### Step 4 — Resolve plan + render summary

Build the plan object: `{ type, name, target_dir, tech_stack, architecture, optional_features, files_to_write }`. Render a summary block (≤ 20 lines) showing:

- Final stack one-liner
- Architecture choice (backend types)
- Optional features chosen
- Abbreviated tree (top 2 levels) — see [references/project-types.md](references/project-types.md) for the canonical per-type trees
- File count

The confirm-merge in Step 3 means we don't re-ask here — we just print the summary before scaffolding. Do not touch the filesystem until "proceed" has been picked.

### Step 5 — Scaffold (no host yarn/node ever)

Create the target directory. Pick the scaffolder branch:

**Frontend / Fullstack frontend half:** bootstrap Vite inside an ephemeral container, then overlay our files.

```bash
docker run --rm -v "$(pwd)/{{name}}":/work -w /work node:20-alpine \
  sh -c "corepack enable && yarn dlx create-vite@latest . --template react-ts"
```

For fullstack, target `./{{name}}/apps/web/` instead of `./{{name}}/`. After the container exits, overlay: `.yarnrc.yml`, `packageManager` field in `package.json`, ESLint config, Vitest config, Dockerfile, CLAUDE.md, the module/layout/shared/routes tree from [references/frontend-modules.md](references/frontend-modules.md), and any auth-layer files from [references/auth-layer.md](references/auth-layer.md). Vite's default `src/App.tsx` is replaced by ours.

**All other types:** direct `Write` calls per the per-type tree in [references/project-types.md](references/project-types.md) and per-file bodies in [references/file-templates.md](references/file-templates.md).

**Auth files** (when auth=yes) come from [references/auth-layer.md](references/auth-layer.md) — both the layer files in `src/shared/auth/` and the pages in `src/modules/auth/`. Pick exactly one adapter file based on the user's chosen method; do not generate the other two.

**Architecture files** (backend) come from [references/architecture-styles.md](references/architecture-styles.md) per the chosen style.

**Database files** (when a DB is selected) come from [references/database-recipes.md](references/database-recipes.md) — the compose service, env keys, and `src/shared/db/client.ts` body.

**Git init** (if git is present and the parent dir is *not* already a repo):

```bash
git init && git add -A && git commit -m "chore: initial scaffold from project-starter"
```

Handle missing `user.name` / `user.email` gracefully (edge case **E18**).

### Step 6 — Build the project image (installs deps inside it)

```bash
cd ./{{name}} && docker compose build
```

This triggers `yarn install --immutable` inside the image. The Dockerfile copies `package.json`, `yarn.lock`, `.yarnrc.yml`, and `.yarn/releases/` before the install line, so Yarn 4 is available at install time. On a first scaffold, `yarn.lock` doesn't exist yet — drop `--immutable` for the first install (the Dockerfile uses `yarn install` plain on first build, then `--immutable` in CI). See [references/docker-recipes.md](references/docker-recipes.md) for the Dockerfile template that handles both cases.

Long-running (~60s). Run in background and surface a "building project image (~60s)" status to the user.

### Step 7 — Verify (all inside Docker)

Run sequentially, surfacing each failure verbatim:

```bash
docker compose run --rm app yarn lint
docker compose run --rm app yarn test
docker compose run --rm app yarn build   # backend / CLI / library only
```

Frontend skips `yarn build` to keep verify fast (Vite production builds take 10–20s). **Do not** run `docker compose up` or `yarn dev` — those are long-running and intended as next-steps.

If any step fails, stop. Treat it as a template bug — do not auto-fix. Point the user at the failing output and suggest filing an issue.

### Step 8 — Print next steps

```
Created: ./{{name}}
Next:
  cd {{name}}
  docker compose up                          # start the dev server
  # then: curl localhost:3000/health
All commands run inside Docker — see CLAUDE.md.
```

For frontend, the dev URL is `http://localhost:5173`. For fullstack, both 3000 and 5173. For library/CLI, omit the curl line.

End the skill.

---

## Reference files

- [project-types.md](references/project-types.md) — per-type folder trees, stack matrix, when to pick which type.
- [file-templates.md](references/file-templates.md) — every file body with `{{placeholders}}`.
- [interview-flow.md](references/interview-flow.md) — exact `AskUserQuestion` payloads.
- [docker-recipes.md](references/docker-recipes.md) — Dockerfile + compose body per type, plus UID/GID and anonymous-volume patterns.
- [database-recipes.md](references/database-recipes.md) — per-DB compose service + client wrapper.
- [architecture-styles.md](references/architecture-styles.md) — modular / layered / clean / hexagonal backend skeletons.
- [frontend-modules.md](references/frontend-modules.md) — module-per-page conventions, lazy-load wiring.
- [auth-layer.md](references/auth-layer.md) — pluggable auth layer: `AuthAdapter` contract, JWT/Session/OAuth adapter bodies.
- [claude-wire.md](references/claude-wire.md) — `CLAUDE.md` + `.claude/settings.json` per type.
- [edge-cases.md](references/edge-cases.md) — recovery procedures.

---

## Silent quality checklist (before showing the summary in Step 4)

1. Project name is kebab-case, non-empty, doesn't traverse paths.
2. Target directory is empty or the user explicitly accepted overwrite.
3. Every reference file body that applies to the chosen type is resolved (no broken `{{placeholder}}` left in any planned file).
4. Exactly one auth adapter is selected when auth=yes; zero when auth=No.
5. The chosen architecture's per-module folder set is selected (modular / layered / clean / hexagonal).
6. `package.json` will have `"type": "module"`, `"packageManager": "yarn@4.x.x"`, vitest in devDeps, no jest.
7. `tsconfig.json` will have `"module": "NodeNext"` for backend/CLI/library; `"module": "ESNext"` and `"moduleResolution": "bundler"` for frontend.
8. `.yarnrc.yml` has `nodeLinker: node-modules`.
9. `.gitignore` ignores `.yarn/*` with explicit `!.yarn/releases` etc.
10. Dockerfile copies `.yarnrc.yml` + `.yarn/releases` before `yarn install`.
11. No `node`, `yarn`, `npm`, or `corepack` command will be issued outside a `docker run` or `docker compose` invocation.
12. `CLAUDE.md` includes the "always go through `docker compose run --rm app`" line, the ESM `.js` suffix rule, the modules-go-in-`src/modules/<name>/` rule, and (when auth=yes) the "never import adapters directly from modules" rule.

If any item fails, fix the plan before scaffolding.

---

## Anti-patterns

- Don't run `yarn install`, `npm install`, or any `node` command on the host. Use `docker run` or `docker compose run` exclusively.
- Don't fall back to handwriting Vite files if the ephemeral-container bootstrap fails. Retry or stop.
- Don't generate more than one auth adapter file. The skill picks exactly one.
- Don't generate an `openapi.yaml` for non-API types (CLI, library, frontend-only). The API-docs question isn't asked for those.
- Don't add Prisma, Drizzle, or Knex without a clear user request — the default DB driver is raw `mysql2`.
- Don't add CommonJS, ts-jest, or jest anywhere — Vitest is the only test runner.
- Don't ask more than two rounds of questions (or three for backend types where Round 2 splits). If something is unclear, default and document the choice in the summary block.
- Don't write a `LICENSE` file by default. Mention it in the README only if the user asks.
- Don't auto-pick the project type. If the user picks "Other", politely decline and list the six supported types.
- Don't run `docker compose up` during verify. Verify is `lint && test && build`.

---

## Limits

- Yarn 4 only. No pnpm, npm, or Bun support in v1.
- Node 20 only (the container's Node version). Older runtimes aren't templated.
- No ORM choice prompt — backend templates use `mysql2` directly. Prisma/Drizzle/Knex live in the CLAUDE.md "future work" list.
- No `LICENSE` generated by default.
- Auth options are stubs only — generated code is enough to wire up sessions/JWT/OAuth at the layer level but doesn't implement a full identity provider.
- The skill writes the **initial state**. It does not check or upgrade scaffolds that already exist.
- CI workflows in scaffolded projects don't use Docker on the runner (they use `setup-node` for speed). A comment at the top of `.github/workflows/ci.yml` calls this out so contributors don't try to run those `yarn` lines locally.
