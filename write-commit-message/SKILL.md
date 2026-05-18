---
name: write-commit-message
description: |
  Drafts a commit message for the current working tree using context-
  first sources (active plan file → session conversation → project-type
  auto-memory → git diff as fallback), cross-checks the chosen message
  against the actual diff for fidelity, mirrors the repo's commit style,
  and asks the user whether to print the message only or stage all
  changes (`git add -A`) and commit. Triggered by `/write-commit-message`
  or when the user explicitly asks for a commit message. Verifies git
  identity before any commit. NEVER bypasses pre-commit hooks
  (`--no-verify`), NEVER amends (`--amend`), NEVER disables signing
  (`--no-gpg-sign`).
version: 1.0.0
allowed-tools: [Bash, Read, AskUserQuestion]
---

# write-commit-message

User-invoked skill for drafting a commit message that faithfully describes the current working tree, and optionally creating the commit. The companion `warn-before-changes` skill handles the "you have uncommitted changes" warning at edit time — this skill is purely about *writing the message*. If the user picks "Stage all changes and commit", this skill commits; otherwise it just prints the message.

---

## When to use

Invoke this skill when:

- The user runs `/write-commit-message`.
- The user asks for a commit message ("write me a commit message", "what should the commit message be").
- `warn-before-changes` told the user to run this skill to save their work first.

## Do not invoke when

- The tree is clean — there is nothing to describe.
- The user is asking for a PR description or changelog entry — those are different artifacts.
- You are about to make new edits — `warn-before-changes` is the right skill for that flow.

---

## Workflow

### Step 1 — Detect git repo

```bash
git rev-parse --is-inside-work-tree 2>/dev/null
```

Non-zero → tell the user "Not a git repository, nothing to do." Return.

### Step 2 — Check for a dirty tree

```bash
git status --porcelain
```

Empty output → tell the user "Working tree is clean, nothing to commit." Return.

### Step 3 — Detect mid-operation state

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

If anything prints, **do not commit silently on top of it**. Surface the state to the user and ask whether to proceed:

- **Continue anyway** — proceed at the user's risk; mid-operation HEAD often produces malformed commits.
- **Stop** *(Recommended)* — abort this skill; let the user finish the merge/rebase/etc. first.

Never run `git merge --abort`, `git rebase --abort`, etc. automatically.

### Step 4 — Verify git identity

Only needed if the user might pick "Stage all changes and commit" in Step 6. Check upfront so the failure is surfaced early:

```bash
git config user.name
git config user.email
```

If **either** is empty, tell the user and show the exact commands (do **not** run them):

```bash
git config --global user.name  "Your Name"
git config --global user.email "you@example.com"
```

Drafting the message is still useful for "Print only" mode, so continue — but disable the "Stage and commit" option in Step 6 until the identity is set.

### Step 5 — Draft the message

Source priority (use the first that yields a faithful description):

1. **Active plan file** — any `~/.claude/plans/*.md` being executed this session.
2. **Session conversation context** — what the user has said about what they were working on.
3. **Auto-memory** — scan `MEMORY.md` for `project`-type entries that overlap the diff.
4. **Git diff** — fallback. Commands to gather signal:

```bash
git status --short
git diff --stat
git diff --cached --stat
git diff             # tracked, unstaged
git diff --cached    # staged
```

For untracked files (not visible in `git diff`):

```bash
git ls-files --others --exclude-standard
# then read each file to understand its content
```

**Always cross-check** the chosen source against `git status --short` + `git diff --stat`. The message must describe the files actually touched, not just the user's intent. If the source and diff diverge, trust the diff and surface the divergence in the Step 6 preview.

**Match the repo's commit style** by sampling recent history:

```bash
git log --oneline -10
```

Classify as Conventional Commits (`feat(scope): subject`), ticket-prefixed (`PROJ-123: ...`), or plain imperative prose. Mirror the dominant pattern. Subject ≤ 70 chars, imperative mood, no trailing period. Add a short bulleted body only when the diff spans multiple distinct concerns.

Full rules + worked examples: [references/commit-message.md](references/commit-message.md).
Exact commands: [references/commands.md](references/commands.md).

### Step 6 — Ask the user what to do

Use `AskUserQuestion` with the drafted subject + body and a preview of `git status --short`:

- **Print message only (Recommended)** — output the message in the chat. Done. Do not touch the index or working tree.
- **Stage all changes and commit** — run:

  ```bash
  git add -A
  git commit -m "<subject>" -m "<body if any>"
  ```

  Capture exit code and stderr. On non-zero exit, see Step 7. Disable this option if Step 4 found a missing git identity.
- **Let me edit the message** — re-prompt the user for the subject (and optional body), then re-ask.
- **Cancel** — return without action.

For a multi-paragraph body, prefer a heredoc so formatting is preserved:

```bash
git commit -m "$(cat <<'EOF'
<subject>

<body line 1>
<body line 2>
EOF
)"
```

Never pass `--no-verify`, `--amend`, `--no-gpg-sign`, `-i`, `--allow-empty`, or `-c commit.gpgsign=false`.

### Step 7 — Handle commit failure

If `git commit` exits non-zero:

- **Pre-commit hook failed** — surface the hook's output verbatim. Stop. Tell the user to fix the underlying issue and re-invoke. Do **not** retry with `--no-verify`. Do **not** amend.
- **Signing failed** (`gpg failed to sign the data`) — surface the error. Stop. Suggest the user fix their GPG/SSH signing setup. Do **not** retry with `--no-gpg-sign`.
- **Author identity unknown** — surface and re-show the `git config --global` commands from Step 4.
- **Any other failure** — surface verbatim. Stop.

Never run `git reset`, `git stash`, `git restore`, `git checkout --`, or `git clean` on failure. The user's working tree must remain untouched so they can debug.

---

## Anti-patterns

- Generic commit messages: `chore: save existing work`, `wip`, `tmp`, `save`, or any content-free string.
- `git add <specific-file>` — always use `git add -A` so untracked files are captured (when the user chose "Stage and commit").
- Running `git config --global user.name/email` automatically. If the identity is missing, *ask the user to configure it*.
- Using `git commit --amend` to fold the new changes into the previous commit.
- Using `--no-verify` to bypass pre-commit hooks that fail.
- Committing on top of an unresolved merge, rebase, cherry-pick, revert, or bisect without explicit user confirmation.
- Auto-running `git commit` when the user only asked for the message text — wait for the explicit "Stage and commit" choice.
- Committing silently — the user must approve via AskUserQuestion.

---

## Limits

- Operates on the single working tree at `$PWD`. Does not recurse into submodules.
- Cannot read the user's mind about ticket numbers when the repo uses ticket-prefixed commits. If you can't find a ticket reference in conversation or memory, drop the prefix and note it in the preview.
- Does not push. Pushing is a separate, deliberate action — leave it to the user or to `/create-pr`.
