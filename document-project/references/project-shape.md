# Project shape detection

Match the strongest signal first; stop at the first definitive hit. If signals overlap (e.g. a service that is also a CLI), keep the top two shapes — section selection respects both.

| Signal at scope root | Shape | Section bias |
|---|---|---|
| `package.json` with `"bin"` field, no server framework dependency | **CLI** | Setup + How to run prominent; no Deploy section unless evidence exists |
| `package.json` with `"main"` / `"exports"`, `"private": false`, no server entry | **Library** | Setup = install instructions; no How to run; no Deploy |
| `Dockerfile` + a server framework dependency (express, fastify, nest, koa, fastapi, flask, django, gin, echo, axum, actix, rails, phoenix…) | **Service** | How to run + How to deploy required; consider DEPLOYMENT.md |
| Deploy workflow present (`.github/workflows/deploy*.yml`, `release.yml` with a deploy job, etc.) + infra file (Terraform, CDK, Serverless, Pulumi…) | **Deployable service** | DEPLOYMENT.md likely; permissions section likely |
| `workspaces` / `pnpm-workspace.yaml` / `lerna.json` / `Cargo.toml [workspace]` / `go.work` | **Monorepo** | Handled in Step 1 — ask user before proceeding |
| Top-level `.py` / `.sh` / `.ts` / `.js` scripts only, no manifest | **Script collection** | Title likely inferred; Setup = how to run each script |
| `next.config*` / `vite.config*` / `astro.config*` / `gatsby-config*` / `remix.config*` / `nuxt.config*` | **Web app** | How to run (dev + build); How to deploy if deploy evidence; no library-style Setup |
| `pyproject.toml` with `[project.scripts]` entry, no web framework | **Python CLI** | Same bias as CLI |
| `pyproject.toml` with `fastapi` / `flask` / `django` dependency | **Python service** | Same bias as Service |
| `Cargo.toml` with `[[bin]]` and no server crate | **Rust CLI** | Same as CLI |
| `Cargo.toml` with `axum` / `actix-web` / `rocket` / `warp` | **Rust service** | Same as Service |
| `go.mod` with `main` package under `cmd/` and no server framework | **Go CLI** | Same as CLI |
| `go.mod` with `gin` / `echo` / `chi` / `fiber` | **Go service** | Same as Service |
| Mix of above (e.g. Library + small CLI; Service + admin scripts) | **Compound** | Keep top two shapes; union their section biases |

## When shape is unclear

If none of the rows match, set shape to `Uncertain`:

- Title gets `(inferred — verify)`.
- What it is gets `(inferred — verify)` on the first sentence.
- Skip "How to run" and "How to deploy" unless explicit commands exist somewhere.
- In Step 11's report, surface the line `Project shape uncertain — verify Title and What it is.`

Do not guess a shape to avoid the `Uncertain` path — accuracy beats coverage.
