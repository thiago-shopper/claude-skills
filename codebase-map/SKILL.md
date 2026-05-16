---
name: codebase-map
description: |
  Use this skill when the user wants to generate or refresh per-folder
  MAP.md files that describe each folder's purpose, files, and
  subfolders, so Claude can navigate the codebase faster and avoid
  recreating things that already exist. Trigger phrases: "map this
  codebase", "generate codebase maps", "refresh the maps", "build
  folder maps", "update MAP.md", "/codebase-map".

  Discovery convention: when entering any folder during normal work, if
  a MAP.md exists there, read it first — it summarizes the folder's
  purpose, files, and subfolders. Treat the "Generated" date as
  advisory; verify against current files before trusting stale entries.
version: 1.0.0
allowed-tools: [Bash, Read, Write, Edit, AskUserQuestion]
argument-hint: [scope path or "full"] [--force]
---

# codebase-map

Generate and refresh per-folder `MAP.md` files across a workspace. Each `MAP.md` states the folder's purpose, lists its direct files and subfolders with one-line descriptions, and serves as Claude's first stop when entering a folder during normal navigation.

This skill speaks **to you, Claude**. Follow the workflow below. The maps are content-driven: you read the actual files in each folder and summarize from what they do, not from filenames alone.

---

## When to use

Invoke this skill when:

- The user asks to "map this codebase", "generate codebase maps", "refresh the maps", "build folder maps", "update MAP.md".
- The user runs `/codebase-map` with or without arguments.
- The user asks Claude to "index the folders" or "describe every folder so you can find things faster".

## Do not invoke when

- The user wants a one-shot summary of a single folder in chat — just read and answer; don't write files.
- The user wants symbol-level or API-level documentation. This skill is folder-level only.
- The repo already has a maintained per-folder docs system the user is happy with.

## Discovery (passive use during normal work)

When you enter a folder for any reason (reading files, planning a change, answering "what's in X"), check whether `MAP.md` exists in that folder and read it first. The `Generated:` date is advisory — verify against current files before relying on stale entries. Don't generate or refresh `MAP.md` passively; only do that when the skill is explicitly invoked.

---

## Workflow

### Step 1 — Resolve scope and dotfolder policy

1. Parse the argument:
   - Path (`./src`, `packages/api`, etc.) → only that subtree.
   - `full` → repo root.
   - Prose argument naming paths ("refresh the maps under src/api and src/auth") → parse paths from prose. If ambiguous, ask via `AskUserQuestion`.
   - No argument → ask the user for scope via `AskUserQuestion`. **Never silently default to full** — large-repo guard.
2. Parse `--force` flag. Default behavior is incremental.
3. **Detect dotfolders in scope** that are not in the hardcoded exclusion list (e.g. `.github`, `.husky`, `.infra`, `.claude`, `.devcontainer`). If any are present, ask the user once via `AskUserQuestion` (`multiSelect: true`) which to include. Cache the selection for the rest of this invocation.

### Step 2 — Detect workspace type

Run `git rev-parse --is-inside-work-tree` (via Bash) in the scope root.

- **Git repo**: use `git ls-files --cached --others --exclude-standard <scope>` to enumerate files. This honors `.gitignore`, `.git/info/exclude`, and the user's global excludes automatically.
- **Non-git**: fall back to `find <scope> -type f` with prune patterns from `references/exclusion-list.md`. Note in the final report that exclusions are heuristic.

### Step 3 — Enumerate target folders

- From the file list, derive the unique set of parent directories within scope.
- Apply the hardcoded exclusion list (`references/exclusion-list.md`) on top of git's view — this catches tracked artifacts and handles non-git workspaces.
- Apply the dotfolder policy from Step 1.
- Always include the scope root itself.

### Step 4 — Decide which folders need regeneration

For each target folder:

1. If no `MAP.md` exists → generate.
2. If `MAP.md` exists, parse its `Generated:` timestamp from the footer.
3. Check `mtime` of every direct child (file or subdir).
4. If any direct child is newer than the `Generated:` timestamp → regenerate.
5. Else skip (mark as up-to-date in the report).

`--force` regenerates every folder in scope regardless of mtime.

### Step 5 — Read folder contents (content-driven)

For each folder that needs regeneration:

1. List direct children (files and subdirs).
2. For each direct **file**:
   - Skip if it matches an exclusion pattern (lock files, minified output, binaries by extension, files > 500 KB by `stat`). List skipped files in the map with a one-line note (e.g. "dependency lockfile — do not edit") but **do not read** them.
   - Otherwise, read with the `Read` tool, `limit: 200`. Enough for docstrings, exports, and obvious purpose without burning tokens on long files.
3. For each direct **subfolder**:
   - If its `MAP.md` already exists, read its `Purpose:` line and reuse it.
   - If not yet processed, write a placeholder entry `(map pending)` — it gets filled when that subfolder's turn comes.

### Step 6 — Synthesize MAP.md content

For each folder:

- **Purpose line** (≤ 160 chars, one sentence): infer from what the files actually do. If genuinely ambiguous after reading, tag the sentence with `(inferred — verify)`. Never write "TBD".
- **Files section**: alphabetical (case-insensitive), one line each, ≤ 100 chars after the dash. Describe what the file is for in plain terms — not its API surface.
- **Subfolders section**: alphabetical, one line each, taken from each subfolder's `Purpose:` line.
- **Apply length caps** (see `references/format-example.md`):
  - Files > 40 → replace with summary line: `(N files; dominant: .ext (count), .ext (count), .ext (count) — run \`ls\` to enumerate)`.
  - Subfolders > 30 → same overflow rule.
- **Preserve block**: if the prior `MAP.md` had text between `<!-- preserve:start -->` and `<!-- preserve:end -->`, copy it into the new file verbatim.

If an existing `MAP.md` lacks the codebase-map footer (foreign content), **ask the user before overwriting**.

### Step 7 — Write the file

Compose the full `MAP.md` content using the format in `references/format-example.md`. Update the footer with today's date. Write via the `Write` tool.

### Step 8 — Report

Print a compact summary at the end:

- Created: N (with paths)
- Updated: N (with paths)
- Skipped (up-to-date): N
- Skipped (exclusion): N (with one-line reason — only if non-trivial)
- Workspace type: git / non-git (and "exclusions heuristic" if non-git)

---

## MAP.md format

See `references/format-example.md` for the concrete shape.

Hard rules:

- Filename is exactly `MAP.md` (uppercase), placed at the root of each folder.
- Sections appear in this order: title, Purpose, Files, Subfolders, preserve block, footer.
- Alphabetical case-insensitive ordering within Files and Subfolders (keeps diffs small).
- Per-entry text after the dash: ≤ 100 chars. Truncate at 97 chars + `...` if longer.
- Files section caps at 40 entries; Subfolders at 30. Overflow becomes a single summary line.

---

## Exclusion list

See `references/exclusion-list.md` for the full set. Summary:

- Folders skipped entirely: `.git`, `node_modules`, `dist`, `build`, `vendor`, `.venv`, `__pycache__`, etc.
- File patterns listed but not read: lockfiles, minified files, images and other binaries, anything > 500 KB.
- Dotfolders not in the skip list (e.g. `.github`, `.husky`, `.infra`) are decided by the user at the start of each run.

---

## Refresh strategy

- **Default: incremental.** Only folders with newer mtimes than their `MAP.md` get regenerated. Keeps diffs surgical on large repos.
- **`--force`**: regenerate every folder in scope.
- **Scope must be explicit.** No argument → ask. Never silently default to full repo.

---

## Limits

- **Description-based discovery** only fires when this skill is in the session's available-skills list. If a future session loads with skills filtered or unavailable, passive `MAP.md` consumption degrades silently. The maps are still useful when read explicitly.
- **Content reading is token-heavy on first run.** On large repos, prefer scoped runs (`/codebase-map ./src`) over `full`. Mention this in the report if a `full` run touches > 100 folders.
- **Folder-level, not symbol-level.** Don't enumerate every exported function or class. File one-liners are the right granularity.
- **Generated files are listed, not read.** Lockfiles, `.min.js`, build output get a one-line tag and no content reading.
- **Non-git workspaces** rely on the hardcoded exclusion list plus `find -prune`. Heuristic, not gitignore-accurate.
- **No auto-staging.** The skill does not run `git add` or commit `MAP.md` files. The user stages and commits manually.
