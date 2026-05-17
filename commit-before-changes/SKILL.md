---
name: commit-before-changes
description: |
  MANDATORY pre-flight before Claude modifies, creates, deletes, formats,
  or refactors any file in a git repository. Invoked automatically by the
  PreToolUse hook on Edit/Write/NotebookEdit whenever the working tree
  may contain pre-existing uncommitted changes, and on demand via
  `/commit-before-changes`. Detects unstaged, staged, and untracked
  changes; if any are found, drafts a commit message context-first
  (active plan file → session conversation → project-type auto-memory
  → git diff as fallback), cross-checks the chosen message against the
  actual diff for fidelity, asks the user to confirm, and creates a
  single commit so the user's in-progress work is never mixed with
  Claude's new edits. If the directory is not a git repo, continues
  normally and tells the user no protection was applied. Never amends,
  rebases, resets, stashes, squashes, or discards work. Never bypasses
  pre-commit hooks with `--no-verify`.
version: 1.0.0
allowed-tools: [Bash, Read, AskUserQuestion]
---

# commit-before-changes

This skill speaks to you, Claude. Run it **before the first file-modifying tool call** (Edit, Write, NotebookEdit, or destructive Bash like `rm`, `mv`, `sed -i`) in each task. Its job is to capture the user's pre-existing uncommitted work in a clean, well-titled commit so your new edits never tangle with theirs.

A complementary `PreToolUse` hook at `~/.claude/skills/.hooks/commit-before-changes.sh` blocks `Edit`/`Write`/`NotebookEdit` when it detects an unprotected dirty tree and points you here.

---

## When to use

Invoke this skill when:

- The `PreToolUse` hook blocks a tool call with a message telling you to run `commit-before-changes`.
- You're about to make the first file modification in a new task and haven't yet confirmed the tree state.
- The user runs `/commit-before-changes` directly.

## Do not invoke when

- The hook's session marker `/tmp/.claude-cbc-${session_id}` already exists (it means this skill has already cleared the tree in this session).
- The dirty changes were made by Claude in this same task — those are your own edits, not pre-existing user work.
- The user has explicitly told you to operate in "scratch mode" and ignore the working-tree state for this session.

---

## Workflow

### Step 1 — Detect git repo

Run:

```bash
git rev-parse --is-inside-work-tree 2>/dev/null
```

- Exit code 0 → continue.
- Non-zero → not a git repo. Tell the user once: "No git protection applied — this directory is not a git repository." Return to the caller. Do not block the original tool call.

### Step 2 — Check for a dirty tree

Run:

```bash
git status --porcelain
```

- Empty output → clean tree. Nothing to do. Return.
- Any output → there is pre-existing work to protect. Continue.

### Step 3 — Detect mid-operation state

Check whether git is currently in the middle of a merge, rebase, cherry-pick, revert, or bisect:

```bash
test -f .git/MERGE_HEAD          && echo merge
test -d .git/rebase-merge        && echo rebase-merge
test -d .git/rebase-apply        && echo rebase-apply
test -f .git/CHERRY_PICK_HEAD    && echo cherry-pick
test -f .git/REVERT_HEAD         && echo revert
test -f .git/BISECT_LOG          && echo bisect
```

If any state is detected, **do not auto-commit** — committing on top of a half-resolved operation produces a malformed commit. Use `AskUserQuestion`:

- **Commit anyway** — proceed at the user's risk.
- **Stop and let me resolve the operation first** *(Recommended)* — abort the skill cleanly; user finishes the merge/rebase/etc., then re-triggers.
- **Abort the in-progress operation** — only if the user explicitly asks; show the exact command (`git merge --abort`, `git rebase --abort`, etc.) and require confirmation. Never run abort commands automatically.

### Step 4 — Verify git identity

Run in parallel:

```bash
git config user.name
git config user.email
```

If **either** is empty, stop the skill immediately and tell the user to configure git. Show the exact commands (do not run them):

```
git config --global user.name  "Your Name"
git config --global user.email "you@example.com"
```

Without an identity, `git commit` will fail or produce a commit with no author. Do not proceed.

### Step 5 — Draft a commit message (context-first, diff as fallback)

The commit message must describe what is being saved. **Never use generic boilerplate like `chore: save existing work`, `wip`, or `tmp`.** Source the message in this priority order, stopping at the first source that yields a faithful description of the dirty work:

1. **Active plan file** at `~/.claude/plans/*.md` if one is being executed in this session. The plan's Context section often names the work-in-progress directly.
2. **Session conversation context** — what the user said they were doing before you touched anything. Phrases like "I was in the middle of refactoring X" or earlier messages that name files now showing in `git status` are the strongest signal.
3. **Auto-memory** — scan `MEMORY.md` for `project`-type entries describing active initiatives; only load the linked file if the index hook mentions files or areas that overlap the diff.
4. **Git diff** — fallback when steps 1–3 don't yield a faithful description. Commands to gather signal:

   ```bash
   git status --short
   git diff --stat
   git diff --cached --stat
   git diff             # tracked, unstaged content
   git diff --cached    # staged content
   ```

**Always cross-check** the chosen source against `git status --short` + `git diff --stat`. The message must honestly describe the files actually touched. If the context says one thing but the diff shows another (e.g. plan mentions "auth" but only `docs/` is dirty), trust the diff and surface the divergence in Step 6's preview.

**Match the repo's commit style** by sampling recent history:

```bash
git log --oneline -10
```

Classify as Conventional Commits (`feat(scope): subject`), ticket-prefixed (`PROJ-123: ...`), or plain imperative prose. Mirror the dominant pattern. Subject ≤ 70 chars, imperative mood, no trailing period. Add a short bulleted body only when the diff spans multiple distinct concerns.

See [references/commit-message.md](references/commit-message.md) for source-priority rules, divergence handling, and worked examples per source.

### Step 6 — Confirm with the user

Use `AskUserQuestion` with the drafted message and a preview of `git status --short`:

- **Commit with this message** *(Recommended once you've cross-checked against the diff)*
- **Let me edit the message** — re-prompt with the edited subject/body.
- **Skip protection and proceed dirty** — the user accepts that Claude's new edits will mix with their existing work. Return to the caller without committing.
- **Stop the task** — abort cleanly, no commit, no further edits.

Never commit silently. The user must approve the message.

### Step 7 — Stage and commit

Exact commands:

```bash
git add -A
git commit -m "<drafted subject>" -m "<drafted body if any>"
```

- Use `git add -A` (not `git add <file>`) so untracked files are captured too.
- Pass the subject and body via separate `-m` flags, or via heredoc through stdin, to preserve formatting.
- Do **not** pass `--no-verify`, `--amend`, `--no-gpg-sign`, or `-i`.

### Step 8 — Handle commit failure

Capture the exit code and stderr from `git commit`. If non-zero:

- **Pre-commit hook failed** — surface the hook's output verbatim. Stop. Tell the user to fix the underlying issue and re-invoke. Do **not** retry with `--no-verify`. Do **not** amend.
- **Signing failed** — surface the error. Stop. Suggest the user fix their GPG/SSH signing setup. Do **not** retry with `--no-gpg-sign`.
- **Any other failure** — surface verbatim. Stop.

Never run `git reset`, `git stash`, or `git restore` on failure. The user's working tree must remain untouched so they can debug.

---

## Anti-patterns

- Using `git stash` to "set aside" the user's work — stashes are easy to forget and lose.
- Using `git reset --hard`, `git checkout .`, or `git restore` to clean the tree.
- Using `git commit --amend` to fold the user's work into an unrelated existing commit.
- Using `--no-verify` to skip pre-commit hooks when they fail.
- Committing on top of an unresolved merge, rebase, cherry-pick, revert, or bisect.
- Committing silently without showing the message and `git status` to the user.
- Generic commit messages: `chore: save existing work`, `wip`, `tmp`, `save`, or any content-free string.
- `git add <specific-file>` — always use `git add -A` so untracked files are captured.
- Running `git config --global user.name/email` automatically. If the identity is missing, *ask the user to configure it*, don't pick values for them.

---

## Limits

- Operates on the single working tree at `$PWD`. Does not recurse into submodules — submodule dirty state must be handled by the user manually.
- Cannot distinguish intentional dirty state from accidental dirty state. It always asks before committing.
- Marker is per Claude session (`/tmp/.claude-cbc-${session_id}`), created by the hook when the tree is clean. If the user makes new edits in their editor mid-session after the marker exists, the hook will not re-trigger. The user can invoke `/commit-before-changes` manually in that case.
- The `PreToolUse` hook fires only for `Edit`, `Write`, and `NotebookEdit`. Destructive Bash commands (`rm`, `mv`, `sed -i`, formatters that rewrite files) are not hooked, because reliably matching them on command text is too brittle. For those, the workflow above is the discipline layer — invoke this skill manually before running such commands.
- Marker creation is the hook's responsibility, not the skill's. The skill commits; the hook's next invocation sees a clean tree and creates the marker on its own.
