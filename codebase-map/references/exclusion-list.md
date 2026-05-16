# Exclusion list

The skill skips these folders entirely and never reads files matching these patterns. The hardcoded list is applied **on top of** `.gitignore` (which `git ls-files` already honors), so it works in non-git workspaces too and catches tracked artifacts.

---

## Folders — skip entirely

Version control:
- `.git`, `.hg`, `.svn`

Dependencies / vendored code:
- `node_modules`, `vendor`, `bower_components`

Build / distribution output:
- `dist`, `build`, `out`, `target`, `bin`, `obj`

Framework caches:
- `.next`, `.nuxt`, `.svelte-kit`, `.astro`, `.cache`, `.parcel-cache`, `.turbo`

Python:
- `.venv`, `venv`, `env`, `__pycache__`, `.pytest_cache`, `.mypy_cache`, `.ruff_cache`, `.tox`, `*.egg-info`

Test / coverage output:
- `coverage`, `.nyc_output`, `htmlcov`

IDE / editor metadata:
- `.idea`, `.vscode`

OS metadata:
- `.DS_Store` (this is a file, listed here for completeness)

---

## Dotfolders — ask the user

These are NOT in the skip list. The skill detects any of these in scope at Step 1 and asks the user whether to include each one:

- `.github` (CI workflows, issue templates)
- `.husky` (git hooks)
- `.infra` (infra-as-code, deploy scripts)
- `.claude` (Claude Code config — may contain user-relevant context)
- `.devcontainer` (Codespaces / Docker dev config)
- `.gitlab`, `.circleci`, `.azure-pipelines` (CI configs)
- Any other dotfolder the user has in the repo

The user's selection is cached for the rest of that invocation only.

---

## File patterns — list with a note, do NOT read

These files appear in `MAP.md` (so navigation still surfaces them) with a fixed one-line tag, but the skill does not Read their contents.

Lockfiles:
- `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`
- `poetry.lock`, `Pipfile.lock`, `uv.lock`
- `Cargo.lock`, `Gemfile.lock`, `composer.lock`, `go.sum`

Minified output:
- `*.min.js`, `*.min.css`, `*.min.mjs`, `*.map`

Images:
- `*.png`, `*.jpg`, `*.jpeg`, `*.gif`, `*.webp`, `*.avif`, `*.ico`, `*.svg` (large), `*.bmp`, `*.tiff`

Other binaries:
- `*.pdf`, `*.zip`, `*.tar`, `*.gz`, `*.bz2`, `*.xz`, `*.7z`, `*.rar`
- `*.exe`, `*.dll`, `*.so`, `*.dylib`
- `*.wasm`, `*.class`, `*.jar`, `*.war`
- `*.mp3`, `*.mp4`, `*.mov`, `*.wav`, `*.ogg`, `*.webm`
- `*.ttf`, `*.otf`, `*.woff`, `*.woff2`, `*.eot`
- `*.parquet`, `*.avro`, `*.arrow`, `*.feather`, `*.pb`, `*.onnx`

Size guard:
- Any file > **500 KB** by `stat`, regardless of extension. Catches unexpected binaries and accidentally-committed large text files.

### Standard tags

| Pattern | Tag |
|---|---|
| Lockfile | `dependency lockfile — do not edit.` |
| `*.min.*`, `*.map` | `minified build output — do not edit.` |
| Image / font / audio / video | `binary asset.` |
| `*.pb`, `*.onnx`, `*.parquet` | `binary data — do not edit by hand.` |
| Other > 500 KB | `large file (N KB) — not summarized.` |

---

## `.gitignore` honoring

In a git repo:

```bash
git ls-files --cached --others --exclude-standard <scope>
```

This respects:
- The repo's `.gitignore` (all of them, including nested).
- `.git/info/exclude`.
- The user's global gitignore (`core.excludesfile`).

The hardcoded folder list above is applied **after** this, as a safety net for artifacts that happen to be tracked despite being build output (rare but real).

---

## Non-git workspaces

Fallback is `find <scope> -type f` plus `-prune` clauses for every entry in the skip-folder list. The skill flags this in its final report:

> Workspace is non-git — exclusions are heuristic; consider `git init` for accurate `.gitignore` handling.
