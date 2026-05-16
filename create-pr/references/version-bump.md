# Version bump — per-ecosystem rules and failure modes

This reference covers the mechanics of how `create-pr` modifies version manifests in Step 4. Keep edits **structured** (parse → mutate → write) wherever possible; only `setup.py` is regex-based.

---

## Detection scope

Non-recursive search at:

- repo root
- `packages/*/` (any depth-1 subdir under `packages/`)
- `apps/*/` (any depth-1 subdir under `apps/`)

Anything deeper or non-standard requires the user to supply the path explicitly.

For each scope, look for any of:

- `package.json`
- `pyproject.toml`
- `setup.py`
- `VERSION`

A scope may have more than one (a polyglot package). Treat each manifest as independent.

---

## Node.js — `package.json` + lockfiles

**Read.** Parse `package.json` as JSON. Version is the top-level `"version"` field.

**Edit.** Parse → mutate `"version"` → write with the file's existing indentation (detect from the raw text; default to 2 spaces). Preserve trailing newline if present.

**Lockfile — `package-lock.json`.** Present in most npm projects. Edit two locations:

1. Top-level `"version"`.
2. Inside `"packages"`, the root entry keyed by `""` — set its `"version"` to match.

Do **not** run `npm install`. The skill is a metadata-only editor.

**Lockfile — `yarn.lock` / `pnpm-lock.yaml`.** Do not edit (their formats don't carry a top-level project version that mirrors `package.json`). Warn the user that the lockfile won't be updated. The bump is still valid; the next `yarn` / `pnpm install` will reconcile.

**Workspaces.** If `package.json` declares `"workspaces"`, treat each workspace `package.json` as a separate manifest (subject to the manifest-selection prompt in Step 3). Do not auto-cascade a root bump into every workspace — that's a user decision.

---

## Python — `pyproject.toml`

**Detection priority within the file:**

1. PEP 621: `[project]` table with `version = "..."`.
2. Poetry: `[tool.poetry]` table with `version = "..."`.

If both exist (rare), prompt the user to choose. If neither exists but the file declares `dynamic = ["version"]`, surface that the version is dynamic (read from a tag or a `__version__.py`) and ask the user to point at the source of truth or skip the bump.

**Edit.** Use a TOML parser that preserves comments and key order (e.g. `tomlkit`-equivalent semantics). If a comment-preserving parser isn't available, fall back to a targeted line replacement: find the first `version = "..."` line inside the matching table and replace only the quoted value. Verify the table context with a regex anchored on the preceding `[project]` / `[tool.poetry]` header so the wrong `version` field (e.g. inside a dependency entry) isn't touched.

---

## Python — `setup.py`

**The one regex case.** Search for a single occurrence of `version="..."` or `version='...'` inside a `setup(...)` call. Pattern (conceptual):

```
\bversion\s*=\s*(['"])([^'"]+)\1
```

If more than one match exists in the file, **abort** and surface both locations — the file likely uses an indirection (e.g. reads from `__version__`) that needs a human.

If `setup.py` exists alongside a `pyproject.toml` with a real version, treat them as separate manifests; the user picks which to bump (or both).

---

## Generic — `VERSION`

A plain-text file at repo root with a single line containing a semver string. Edit by overwriting with the new version plus a trailing newline (match whatever the file already has).

---

## Version-string semantics

Parse current version as `MAJOR.MINOR.PATCH[-pre][+build]`.

- **Pre-release suffix present** (e.g. `1.2.3-rc.1`): prompt the user — drop the suffix and bump the core, keep the suffix and bump the core, or abort. Do not silently strip.
- **Build metadata** (`+build`): preserve unless the user opts to drop it.
- **Non-semver** (e.g. `0.0.1.dev3+local`, `2024.05.16`): abort. Print the offending value and ask the user to set the target version manually.

**Bump arithmetic:**

| From | Major bump | Minor bump | Patch bump |
|---|---|---|---|
| `1.2.3` | `2.0.0` | `1.3.0` | `1.2.4` |
| `0.x.y` | `1.0.0` (warn: leaving 0.x) | `0.(x+1).0` | `0.x.(y+1)` |

When current major is `0`, surface the convention that minor bumps can carry breaking changes in pre-1.0 projects — but follow the user's pick; do not second-guess.

---

## Multi-manifest reconciliation

When the user selects more than one manifest to bump in Step 3:

1. Collect each manifest's current version.
2. If all current versions match, propose the same next version for all.
3. If they differ, prompt:
   - **Advance each independently** (each manifest gets its own next-version based on its current).
   - **Sync to a shared target version** (user types or picks one).
   - **Abort.**

Don't try to be clever about "should they be in sync" — the user knows.

---

## Failure modes — full table

| Trigger | Behavior |
|---|---|
| Not a git repo / `gh` not authed | abort with verbatim CLI error (Step 1) |
| Empty `git status` | skip Step 2 |
| User picks "abort" in Step 2 | exit cleanly; no edits, no commits |
| No manifest found in any scope | prompt: supply a path / skip bump / abort |
| Manifest present but `version` field missing | abort; print path + field name; don't invent a starting version |
| Manifest unparseable (malformed JSON/TOML) | abort; print parse error; don't write |
| `pyproject.toml` declares `dynamic = ["version"]` | prompt for source-of-truth path or skip bump |
| `setup.py` has >1 `version=...` match | abort; list locations |
| Current version is non-semver | abort; print value; ask user to set target manually |
| Pre-release suffix on current version | prompt: drop suffix / keep suffix / abort |
| Multiple manifests, different current versions | prompt: advance each / sync target / abort |
| Active lockfile is `yarn.lock` / `pnpm-lock.yaml` | warn lockfile won't be touched; ask proceed / abort |
| `package-lock.json` already has uncommitted drift | surface drift; ask proceed / abort (a real `npm install` may be needed by hand) |
| User picks "skip bump" in Step 3 | run Step 2's pending commit if any; continue to Step 5 without touching manifests |
| User picks "abort" in Step 3 or Step 4 | exit cleanly; no edits, no commits — if files were staged earlier, unstage with `git reset HEAD` after user confirms |
| Pre-commit hook fails on the bump commit | surface output verbatim; do NOT `--no-verify`; do NOT `--amend`; instruct user; exit |
| Branch already pushed and remote ahead | abort the push step in Step 11; ask user to resolve before continuing |

---

## What this skill explicitly does not do

- Doesn't run `npm install`, `poetry lock`, `pip install -e .`, or any package-manager command. Manifest edits only.
- Doesn't generate or update `CHANGELOG.md`. (A future skill can do that.)
- Doesn't create git tags. The bump commit is enough; tagging is a separate decision tied to release.
- Doesn't validate that the new version doesn't already exist on a registry (npm, PyPI). The user owns that check.
- Doesn't cascade a monorepo root bump into all workspaces.
