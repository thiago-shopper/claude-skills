---
name: warn-before-changes
description: |
  MANDATORY pre-flight warning when Claude is about to modify, create,
  delete, format, or refactor any file in a git repository that has
  pre-existing uncommitted changes. Invoked automatically by the
  PreToolUse hook on Edit/Write/NotebookEdit whenever the working tree
  is dirty, and on demand via `/warn-before-changes`. Shows the user
  the current dirty state (`git status --short` + `git diff --stat`),
  flags any mid-operation state (merge/rebase/cherry-pick/revert/
  bisect), and asks for explicit permission via AskUserQuestion
  (Proceed once / Proceed for session / Stop). NEVER stages, commits,
  stashes, resets, or otherwise touches the index or working tree. If
  the user wants to save their work first, suggest
  `/write-commit-message`. If the directory is not a git repo, the
  skill exits silently with no protection applied.
version: 1.0.0
allowed-tools: [Bash, AskUserQuestion]
---

# warn-before-changes

This skill speaks to you, Claude. Run it **before the first file-modifying tool call** (Edit, Write, NotebookEdit, or destructive Bash like `rm`, `mv`, `sed -i`) in each task whenever the PreToolUse hook flags pre-existing uncommitted work. Its only job is to show the user the dirty state and get explicit permission before your edits proceed. **It must not write, stage, or commit anything.**

A companion `PreToolUse` hook at `~/.claude/skills/.hooks/warn-before-changes.sh` blocks `Edit`/`Write`/`NotebookEdit` when it detects a dirty tree that hasn't been acknowledged this session, and points you here.

---

## When to use

Invoke this skill when:

- The `PreToolUse` hook blocks a tool call with a message telling you to run `warn-before-changes`.
- You're about to make the first file modification in a new task and haven't yet confirmed the tree state.
- The user runs `/warn-before-changes` directly.

## Do not invoke when

- The session marker `/tmp/.claude-wbc-${session_id}` already exists — the user has already chosen "Proceed for session" or the hook has marked a clean tree.
- The dirty changes were made by Claude in this same task — those are your own edits, not pre-existing user work.
- The user has explicitly told you to operate in "scratch mode" and ignore the working-tree state for this session.

---

## Workflow

### Step 1 — Detect git repo

```bash
git rev-parse --is-inside-work-tree 2>/dev/null
```

- Exit code 0 → continue.
- Non-zero → not a git repo. Tell the user once: "No protection applied — this directory is not a git repository." Return to the caller. Do not block the original tool call.

### Step 2 — Check for a dirty tree

```bash
git status --porcelain
```

- Empty output → clean tree. Nothing to warn about. Return.
- Any output → continue.

### Step 3 — Detect mid-operation state

Check whether git is in the middle of a merge, rebase, cherry-pick, revert, or bisect:

```bash
{
  [ -f .git/MERGE_HEAD ]       && echo "merge in progress"
  [ -d .git/rebase-merge ]     && echo "interactive rebase in progress"
  [ -d .git/rebase-apply ]     && echo "rebase/am in progress"
  [ -f .git/CHERRY_PICK_HEAD ] && echo "cherry-pick in progress"
  [ -f .git/REVERT_HEAD ]      && echo "revert in progress"
  [ -f .git/BISECT_LOG ]       && echo "bisect in progress"
} 2>/dev/null
```

If anything prints, include it verbatim in the warning preview in Step 4 so the user understands the tree is in a sensitive state. **Do not branch the workflow** — the same 3 options apply. It is the user's call whether to proceed in that state.

### Step 4 — Warn the user and get explicit permission

Gather a compact preview:

```bash
git status --short
git diff --stat
```

Truncate the `git status --short` preview to the first 20 lines and indicate truncation if needed. Then call `AskUserQuestion` with the question:

> "Your working tree has uncommitted changes. Claude is about to edit files. How should we proceed?"

Include in the question body:
- `git status --short` preview (truncated)
- `git diff --stat` preview
- Any mid-operation state detected in Step 3
- A note: "To save your work first, run `/write-commit-message` after picking Stop."

Options:

- **Proceed once** — allow this one edit only. The next edit will warn you again.
  - Write the one-shot marker: `touch "/tmp/.claude-wbc-once-${session_id}"`
  - Return so Claude retries the original tool call. The hook consumes the marker on the retry, then re-blocks on the edit after.
- **Proceed for session (Recommended)** — allow all edits this session without further warning.
  - Write the persistent session marker: `date -u +%Y-%m-%dT%H:%M:%SZ > "/tmp/.claude-wbc-${session_id}"`
  - Return. The hook fast-paths every subsequent tool call this session.
- **Stop** — do not proceed.
  - Do **not** write either marker.
  - Return to the caller and tell the user: "Stopped. If you want to save your work first, run `/write-commit-message`." Do not retry the edit.

### Step 5 — Hard rules

- Never run `git add`, `git commit`, `git stash`, `git reset`, `git restore`, `git checkout --`, or `git clean`.
- Never edit files in the working tree.
- Never write a marker the user did not explicitly choose.
- Never silently allow the edit — the user must pick an option.

The `${session_id}` for marker filenames is the PreToolUse `session_id`. If you don't have it readily available, read it from the hook's blocking stderr message context, or fall back to the literal string `unknown` (this matches the hook's fallback so the markers still match).

---

## Anti-patterns

- Auto-committing the dirty state — that is the job of `/write-commit-message`, not this skill.
- `git stash` to "set aside" the user's work — stashes are easy to forget and lose.
- `git reset --hard`, `git checkout .`, or `git restore` to clean the tree.
- Writing the session marker before the user has chosen "Proceed for session".
- Proceeding silently because the warning "felt unnecessary" — always ask.
- Suggesting `--no-verify` or any flag that bypasses repo hooks.

---

## Limits

- Operates on the single working tree at `$PWD`. Does not recurse into submodules — submodule dirty state must be handled by the user manually.
- Cannot distinguish intentional dirty state from accidental dirty state. It always asks.
- Markers are per Claude session:
  - `/tmp/.claude-wbc-${session_id}` — persistent (set by hook on clean trees and by this skill on "Proceed for session")
  - `/tmp/.claude-wbc-once-${session_id}` — one-shot, consumed by the hook on the next edit
- The `PreToolUse` hook fires only for `Edit`, `Write`, and `NotebookEdit`. Destructive Bash commands (`rm`, `mv`, `sed -i`, formatters that rewrite files) are not hooked, because reliably matching them on command text is too brittle. For those, the workflow above is the discipline layer — invoke this skill manually before running such commands.
