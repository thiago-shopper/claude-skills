# Section rules

For each candidate section, when to fire, when to skip, how to write it, and how long it should be. Walk top to bottom during Step 6.

---

## 1. Title + tagline

- **Fires**: always.
- **Content**: Project name from the manifest (`package.json` `name`, `pyproject.toml` `[project] name`, `Cargo.toml` `[package] name`, etc.). Tagline derived from the manifest's `description` / `summary`. If absent, infer one sentence from entry-point file headers + Dockerfile `CMD` + main script.
- **Length**: 1 H1 line + 1 sentence.
- **Mark inferred**: if tagline is inferred, append `(inferred — verify)` at the end of the sentence.

## 2. What it is

- **Fires**: always.
- **Content**: 2–4 sentences of prose. What it does, who runs it, what it produces. Concrete language. No "the project aims to" / "this is designed to".
- **Length**: 2–4 sentences.

## 3. Why it exists

- **Fires**: a source explains the *why* — existing README's intro paragraph, a `docs/MOTIVATION*`, a `CLAUDE.md` section, or a `docs/adr*` decision.
- **Skips**: no source surfaces a "why".
- **Content**: 1–3 sentences pulling from the source. Never invent strategic rationale.

## 4. Tech stack at a glance

- **Fires**: any manifest exists.
- **Skips**: pure script collection with no manifest.
- **Content**: one-line bullets covering language + runtime version (from `engines` / `python-requires` / `rust-toolchain`), framework (from dependencies), datastore (from compose / env example), top 3 key libraries.
- **Length**: ≤ 6 bullets.

## 5. Setup

- **Fires**: any installable manifest, or an explicit `Makefile` / `justfile` install target.
- **Skips**: pure docs repo.
- **Content**: numbered steps with real commands. Cover: clone, install, copy env file (if `.env.example` exists), first build/run. Each step = command + one short description.
- **Length**: 3–6 steps.

## 6. Environment variables

- **Fires**: `.env.example` (or `.sample` / `.template`) exists, OR env vars are referenced in code.
- **Skips**: no env config of any kind.
- **Content**: markdown table or bulleted list of variable names + one-line purpose + required/optional. **Never include values.** If a variable is referenced in code but not in any example file, list it with `(source: <path>)` and note the missing example file.

## 7. How to run

- **Fires**: Service / CLI / Web app shape.
- **Skips**: Library shape (publishing instructions go in Setup or Tech stack).
- **Content**: real commands from scripts or Dockerfile entrypoint. State port / endpoint / produced output.
- **Length**: 1–4 lines per mode.

## 8. How to test

- **Fires**: any test config or test script exists.
- **Skips**: no tests detectable.
- **Content**: exact test commands from `scripts` / `Makefile`. Mention the test framework. If a coverage script exists, mention it on a separate line.
- **Length**: 2–5 lines.

## 9. How to deploy

- **Fires**: deploy workflow, infra file, or Procfile present.
- **Skips**: none of those.
- **Content**: describe the actual mechanism in prose — e.g., "Pushes to `main` trigger `.github/workflows/deploy.yml`, which builds the image and pushes to ECR; the service runs on Fargate per `infra/main.tf`." Do not restate YAML.
- **Length**: 3–8 sentences. If it would exceed 8, split into DEPLOYMENT.md and leave a 1–2 sentence summary + link in README.

## 10. Architecture overview

- **Fires**: existing `ARCHITECTURE*`, or non-trivial layout (≥ 3 top-level modules under `src/` with a clear entrypoint), or ADR directory.
- **Skips**: single-file script, or two-file project.
- **Content**: 1 paragraph describing data / control flow. Reference real folder names. If ≥ 5 modules or an `ARCHITECTURE.md` is being generated, the README section is one paragraph + link.
- **Length**: 1 paragraph.

## 11. Permissions / Claims

- **Fires**: Step 2's grep surfaced a structured source — an enum, a config object, a constants module declaring permissions / claims / roles / scopes.
- **Skips**: no structured source, or only scattered string literals (in that case, use a bulleted list instead of a table).
- **Content (table form)**: markdown table with columns `Claim | Purpose | Required for`. Rows come directly from the source.
- **Content (list form)**: one bullet per claim with a one-line purpose.

## 12. External setup / Integrations

- **Fires**: code references external SaaS (Stripe, Twilio, Sentry, S3, OpenAI, etc.) OR env example names them.
- **Skips**: none found.
- **Content**: bulleted list. Each bullet: name, what it's used for, what you need (API key, project ID), where to put it (which env var, which config file).
- **Length**: 1 line per integration.

## 13. Related projects

- **Fires**: existing README references siblings, OR monorepo has sibling packages, OR `package.json` `repository` points to a known org with siblings (do not invent siblings; only list what you can verify).
- **Skips**: no evidence.
- **Content**: bulleted list of name + 1 line + link (if URL is in evidence).
- **Length**: ≤ 8 bullets.

## 14. Contributing

- **Fires**: strong evidence (`CONTRIBUTING.md` already exists, PR template, commit-style config). When evidence is strong enough to also fire CONTRIBUTING.md generation, this section becomes a one-paragraph stub + link.
- **Skips**: no evidence — do not include generic "fork the repo, open a PR" boilerplate.
- **Content**: 1 paragraph + link to CONTRIBUTING.md if it exists or is being written this run.

## 15. License

- **Fires**: LICENSE file exists at the scope root.
- **Skips**: no LICENSE.
- **Content**: 1 line — license name + link to the file.

---

## When in doubt: omit

A short, accurate README is the goal. If a section's evidence is thin, **omit it**. The report at Step 11 will list omitted sections with one-word reasons — that is the right place to flag what's missing, not a stub in the document itself.
