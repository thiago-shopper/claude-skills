---
name: document-project
description: |
  Use this skill when the user wants to generate, write, or refresh
  project-level documentation files (README.md, and when evidence
  supports them CONTRIBUTING.md / ARCHITECTURE.md / DEPLOYMENT.md) for
  a software project, grounded in what the codebase actually contains.
  Trigger phrases: "document this project", "write the README",
  "generate README", "refresh the README", "create project docs",
  "the README is out of date", "/document-project".

  Behavior:
  - Reads project signals (manifests, CI configs, infra files, env
    examples, existing docs) to decide project shape and which
    sections apply. Omits sections without evidence.
  - Voice is human-to-human: short, direct, no marketing language,
    no invented commands.
  - Asks per file before overwriting any existing doc with
    hand-written content (three-way: refresh / overwrite / skip).

  Do not invoke when:
  - The user wants CLAUDE.md (instructions for Claude) — that is the
    builtin /init.
  - The user wants per-folder MAP.md — that is /codebase-map.
  - The user asks "what's in this repo" / "explain this project" in
    chat — answer in chat; do not write files.
  - The user wants API reference, docstrings, code comments, or
    symbol-level docs.
  - The user wants a PR description, commit message, or changelog.
  - The user mentions "the readme" in passing during unrelated work
    without asking for it to be written or updated.
version: 1.0.0
allowed-tools: [Bash, Read, Write, Edit, Grep, Glob, AskUserQuestion]
argument-hint: [path | "here"]
---

# document-project

Generate or refresh project-level documentation — README.md primarily, plus CONTRIBUTING.md / ARCHITECTURE.md / DEPLOYMENT.md when the project has enough evidence to support them. Every claim in the output comes from a file you actually read. Sections without evidence are omitted; empty sections are worse than terse ones.

This skill speaks **to you, Claude**. Follow the workflow below. The output is **content-driven**: you read the actual manifests, configs, and code, and write only what those files tell you.

---

## When to use

Invoke this skill when:

- The user asks to "document this project", "write the README", "generate README", "refresh the README", "create project docs".
- The user says "the README is out of date" / "the docs are stale".
- The user runs `/document-project` with or without an argument.

## Do not invoke when

- The user wants CLAUDE.md → that is the builtin `/init`, not this skill.
- The user wants per-folder navigation maps → that is `/codebase-map`.
- The user wants an in-chat answer about what the project does — answer in chat; do not write files.
- The user wants API reference, docstrings, inline comments, or symbol-level docs.
- The user wants a PR description (use `/create-pr`), commit message, or changelog.
- The user mentions "the readme" in passing during unrelated work without asking for it to be written or refreshed.

---

## Workflow

### Step 1 — Resolve scope

1. Argument forms: a path (`./packages/api`), `here`, or empty.
2. Empty argument → use cwd as the scope root.
3. **Detect monorepo signals** at the scope root:
   - `package.json` containing a `"workspaces"` field
   - `pnpm-workspace.yaml`
   - `lerna.json`
   - `Cargo.toml` containing a `[workspace]` section
   - `go.work`

   If any are present, ask via `AskUserQuestion`: document the root project, one specific subproject, or one README per workspace. **Never silently default to "root".**
4. The scope root becomes the directory where docs are read from and written to.

### Step 2 — Project introspection (read-only, tight)

Read these at the scope root, in this order. Use `Read` with `limit: 150–200`. Stop reading a category once you have enough evidence.

- **Manifests**: `package.json`, `pyproject.toml`, `setup.py`, `Cargo.toml`, `go.mod`, `Gemfile`, `composer.json`, `pom.xml`, `build.gradle*`, `mix.exs`, `pubspec.yaml`.
- **Runtime / containerization**: `Dockerfile`, `docker-compose*.yml`, `Procfile`.
- **CI/CD**: first 2 files in `.github/workflows/`, `.gitlab-ci.yml`, `.circleci/config.yml`.
- **Infra**: `terraform/`, `infra/`, `cdk.json`, `serverless.yml`, `wrangler.toml`, `vercel.json`, `netlify.toml`, `fly.toml`, `app.yaml`, `k8s/`, `helm/` (existence + one representative file).
- **Env / config**: `.env.example`, `.env.sample`, `.env.template`, `config/`, `settings/`. **Never read `.env`, `.env.local`, `.env.production`, or any file matching that pattern** — secrets must not leak into docs.
- **Tests**: `jest.config*`, `vitest.config*`, `pytest.ini`, `tox.ini`, `Makefile`, `justfile`, `pre-commit-config.yaml`, manifest `scripts` block.
- **Entry points**: `ls` only — `src/`, `cmd/`, `bin/`, `app/`, `pages/`, `routes/`. Don't read source.
- **Existing docs**: full read (no limit) of `README*`, `CONTRIBUTING*`, `ARCHITECTURE*`, `DEPLOYMENT*`, `CHANGELOG*`, top-level `MAP.md`, `docs/` index files.
- **Permission signals**: `Grep` for `claim|permission|role|RBAC|scope|policy|authorize` against `src/`. Cap to 30 matched files; read the top 5 hits with `limit: 100`.

### Step 3 — Detect project shape

Apply the signal → shape table from `references/project-shape.md`. The detected shape drives section selection in Step 6.

### Step 4 — Decide which files to generate

README.md is always considered. Decide each extra independently:

- **CONTRIBUTING.md** — fire if any of: existing `CONTRIBUTING*`, `.github/PULL_REQUEST_TEMPLATE*`, commit-style config (`commitlint`, `.gitmessage`, `husky` commit hooks), `CODE_OF_CONDUCT.md`, `CODEOWNERS`.
- **ARCHITECTURE.md** — fire if any of: existing `ARCHITECTURE*`, `docs/architecture*`, ≥ 5 top-level modules under `src/` (or equivalent) with a clear entrypoint, ADR directory (`docs/adr*`, `decisions/`).
- **DEPLOYMENT.md** — fire if deploy evidence (CI deploy job OR infra file OR Procfile) would push the README's deploy section past ~8 sentences. Otherwise the deploy content stays inline in README.

**< 4-sentence rule.** If a candidate extra fires but the resulting file would be less than 4 sentences of real content, **don't write it** — keep that content inline in README instead. Empty or near-empty files are worse than a terser README.

### Step 5 — Per-file existing-content handling

For **each** file you will write (README + each fired extra):

1. If the file doesn't exist → generate fresh.
2. If the file exists, has the skill's footer marker (Step 10), and has no hand-written prose outside `<!-- preserve:start --> ... <!-- preserve:end -->` markers → refresh silently.
3. If the file exists and contains hand-written prose outside preserve markers → ask via `AskUserQuestion` with these three options (recommend the first):
   - **Refresh in place** (recommended): keep sections that still match reality, rewrite stale ones, add missing load-bearing sections, copy preserve blocks byte-identical.
   - **Overwrite from evidence**: regenerate from scratch using only what Step 2 found.
   - **Skip this file**: leave it alone; continue with the others.

Preserve syntax mirrors `/codebase-map` for consistency: `<!-- preserve:start -->` and `<!-- preserve:end -->`.

### Step 6 — Section selection

Walk the catalog in `references/section-rules.md`. Include only sections whose fire condition matches the evidence collected in Step 2. **Omission is informative** — never include a section to "be thorough". A short, accurate README is the goal; do not pad.

### Step 7 — Content extraction rules

- **Commands**: emit a command only if (a) it appears in `scripts`, `Makefile`, `justfile`, manifest tool config, OR (b) is the canonical install for the detected stack (`pip install -e .`, `cargo build`, `go build ./...`, `npm install`). Never invent.
- **Env vars**: extract names from `.env.example` / `.env.sample` / `.env.template` only. Never include values. If code references env vars not in any example file, list the name with `(source: <path>)` and note the missing example.
- **Deploy**: describe the actual observed mechanism in prose. Don't restate YAML.
- **Permissions / claims**: if Step 2's grep surfaced a structured source (enum, config object, constants module), emit a markdown table with `Claim | Purpose | Required for`. If only scattered string literals exist, emit a bulleted list instead — a half-empty table is worse than a clean list.
- **External integrations**: surface SaaS / third-party services referenced in code or env example. One line each: name, what it's for, what credential is needed, where to put it.

### Step 8 — Voice pass (silent)

Apply the rules in `references/voice-rules.md`. Strip banned words from `references/banned-words.md`. Convert template-flavored openings ("This project aims to provide…") into direct sentences ("Indexes invoices and exports them as CSV."). Prose for descriptive sections; bullets for genuine lists only.

### Step 9 — Quality checklist (silent, before any Write)

Run through these. If anything fails, fix and re-check.

1. Every command in the doc appears in a file you read.
2. No invented URLs, package names, ports, or paths.
3. No `TBD`, `Lorem`, or placeholder text.
4. No banned words from `references/banned-words.md`.
5. No section is < 2 sentences AND < 2 bullets — if it's that thin, omit it.
6. Title is the project's actual name from the manifest (not a slug, not the directory name unless that's all you have).
7. If preserve blocks existed in the prior file, they are byte-identical.
8. If "refresh in place" was chosen, untouched paragraphs are byte-identical to the original.
9. Section order matches `references/section-order.md`.
10. Cross-doc links resolve — README's "See ARCHITECTURE.md" points to a file you are actually writing in this run.

### Step 10 — Write

One `Write` call per file. End each generated file with this footer:

```html
<!-- generated by /document-project on YYYY-MM-DD; preserve blocks honored -->
```

The footer is how Step 5 detects "is this file fully auto-generated".

### Step 11 — Report

Print a compact summary at the end:

- **Files written** (full paths).
- **Per file**: `fresh` / `refreshed` / `overwritten` / `skipped` and a one-line reason for `skipped`.
- **Sections included** and **sections omitted** with one-word reasons (`no CI`, `no env example`, `no permissions found`).
- **Files considered but not written** because of the < 4-sentence rule or the user choosing `skip`.

---

## Section catalog (summary)

Full rules in `references/section-rules.md`. Render order in `references/section-order.md`.

| # | Section | Fires when | Length |
|---|---|---|---|
| 1 | Title + tagline | Always | 1 line + 1 sentence |
| 2 | What it is | Always | 2–4 sentences |
| 3 | Why it exists | Source surfaces a stated purpose | 1–3 sentences |
| 4 | Tech stack at a glance | Any manifest exists | ≤ 6 bullets |
| 5 | Setup | Installable manifest or explicit install target | 3–6 steps |
| 6 | Environment variables | `.env.example` exists or env vars in code | as needed |
| 7 | How to run | Service / CLI / web app shape | 1–4 lines per mode |
| 8 | How to test | Test config or test script exists | 2–5 lines |
| 9 | How to deploy | Deploy workflow / infra / Procfile | 3–8 sentences (or split to DEPLOYMENT.md) |
| 10 | Architecture overview | Non-trivial layout | 1 paragraph (or link to ARCHITECTURE.md) |
| 11 | Permissions / Claims | Grep finds structured source | table or list |
| 12 | External setup / Integrations | Code or env example references SaaS | 1 line per |
| 13 | Related projects | Existing README references siblings, or monorepo siblings | ≤ 8 bullets |
| 14 | Contributing | Strong evidence (else link to CONTRIBUTING.md) | 1 paragraph |
| 15 | License | LICENSE file exists | 1 line |

Whole-document length: 150–500 words for libraries/CLIs, 300–800 for services. **Hard cap 1200 words** — anything longer must split into ARCHITECTURE / DEPLOYMENT.

---

## Voice rules (summary)

Full content in `references/voice-rules.md`.

**Do**: write like one engineer telling another what they need to be productive in 10 minutes. Short sentences. Prose for descriptive sections; bullets only for genuine lists. Backticks for real commands. Pull verbatim from manifests, code, and existing docs. Mark inferences explicitly: `(inferred from Dockerfile — verify)`.

**Don't**: marketing words, hedge words, filler openings, boilerplate Prerequisites lists, invented commands, emoji headings, badges, "Made with love" footers (unless the file being refreshed already has them), bullet padding.

---

## Limits

- **Scope is project-level, not symbol-level.** Don't document individual functions or classes. Use `/codebase-map` for folder navigation; use docstrings / inline comments for API.
- **Description-based discovery only fires when this skill is in the session's available-skills list.** If skills are filtered or unavailable, the skill is dormant.
- **Never reads `.env` / `.env.local` / `.env.production`.** Only the `.env.example` family is safe to read.
- **No staging or committing.** The skill writes files; the user stages and commits.
- **Language**: write in English unless the existing README is in another language — then match it (mirrors `/create-pr`'s template-language convention).
