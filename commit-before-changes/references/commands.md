# commit-before-changes — exact commands reference

Copy-paste commands for each workflow step. Use these verbatim — they're chosen for predictable behavior and minimal side effects.

---

## Step 1 — Detect git repo

```bash
git rev-parse --is-inside-work-tree 2>/dev/null
```

Exit code 0 → in a work tree. Anything else → not a git repo.

---

## Step 2 — Check for dirty tree

```bash
git status --porcelain
```

Output legend (column 1 = index, column 2 = work tree):

| Code | Meaning |
|---|---|
| ` M` | Modified in work tree, not staged |
| `M ` | Staged modification |
| `MM` | Staged modification + further unstaged changes |
| `A ` | Newly added, staged |
| `??` | Untracked |
| `D ` / ` D` | Deleted |
| `R ` | Renamed |
| `UU` | Both modified (unmerged) |

Empty output → clean tree, skip the rest of the workflow.

---

## Step 3 — Detect mid-operation state

Run as a single block:

```bash
{
  [ -f .git/MERGE_HEAD ]        && echo "merge in progress"
  [ -d .git/rebase-merge ]      && echo "interactive rebase in progress"
  [ -d .git/rebase-apply ]      && echo "rebase/am in progress"
  [ -f .git/CHERRY_PICK_HEAD ]  && echo "cherry-pick in progress"
  [ -f .git/REVERT_HEAD ]       && echo "revert in progress"
  [ -f .git/BISECT_LOG ]        && echo "bisect in progress"
} 2>/dev/null
```

If anything prints, ask the user — do NOT auto-commit on top of a half-resolved operation.

---

## Step 4 — Verify git identity

```bash
git config user.name
git config user.email
```

Either empty → stop. Suggested setup commands to show the user (never auto-run):

```bash
git config --global user.name  "Your Name"
git config --global user.email "you@example.com"
```

If the user wants per-repo identity instead, drop `--global`.

---

## Step 5 — Gather diff signal

```bash
git status --short          # one-line-per-file summary
git diff --stat             # line counts per tracked, unstaged file
git diff --cached --stat    # line counts per staged file
git diff                    # full unstaged diff
git diff --cached           # full staged diff
git log --oneline -10       # detect repo commit style
```

For very large diffs, prefer `--stat` plus the first ~200 lines of the full diff to bound token usage.

For untracked files, the diff is not in `git diff` output. Inspect each untracked file directly:

```bash
git ls-files --others --exclude-standard   # list untracked files
# then `cat` or `head` each one to understand its content
```

---

## Step 7 — Stage and commit

```bash
git add -A
git commit -m "<subject>" -m "<body>"
```

Or, if the body has multiple paragraphs / preserve-formatting concerns, use a heredoc:

```bash
git add -A
git commit -m "$(cat <<'EOF'
<subject>

<body line 1>
<body line 2>
EOF
)"
```

**Never** pass any of: `--no-verify`, `--amend`, `--no-gpg-sign`, `-i`, `--allow-empty`, `-c commit.gpgsign=false`.

---

## Step 8 — Inspect commit failure

If `git commit` exits non-zero:

```bash
# Capture exit code AND stderr in one go
git commit -m "..." 2>&1
echo "exit=$?"
```

Common failures:

| Output contains | Cause | Action |
|---|---|---|
| `pre-commit hook failed` or specific linter output | Repo's pre-commit hook rejected the commit | Stop. Surface output. Tell user to fix and re-invoke. |
| `gpg failed to sign the data` | Signing key missing or expired | Stop. Suggest fixing GPG config. |
| `Author identity unknown` | user.name/email not set | Should have been caught in Step 4 — re-check. |
| `nothing to commit, working tree clean` | Race: tree became clean between Step 2 and Step 7 | Return success silently. |

After any failure, **do not** run:

- `git reset` (any flavor)
- `git stash`
- `git restore`
- `git checkout --`
- `git clean`

Leave the user's tree exactly as it was so they can debug.
