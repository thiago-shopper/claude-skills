---
name: create-pr
description: |
  Use this skill when the user wants to open a GitHub pull request from the
  current branch. Trigger phrases: "create a PR", "open a pull request",
  "/create-pr", "ship this branch", "make a PR". Produces a concise,
  objective title + body (Purpose / Summary / Test plan, or the repo's own
  template if one is present) and opens the PR via `gh pr create`. The
  user MUST specify the target/base branch — the skill never auto-picks
  one. If no target is supplied, the skill halts and asks (no suggestions,
  no defaults). Also detects an existing open PR for the branch and
  offers to update its body instead of creating a duplicate.
version: 1.0.0
allowed-tools: [Bash, Read]
argument-hint: <target branch> [optional PR notes]
---

# create-pr

Turn the current branch into a pull request whose description is **objective and concise** — it states the *why*, summarizes the change in grouped bullets, and lists a real test plan. Honors any repo-local PR template. Never auto-picks the target branch.

---

## When to use

Invoke this skill when:

- The user runs `/create-pr <target>` or `/create-pr` with no argument.
- The user says "create a PR", "open a pull request", "make a PR for this branch", "ship this".
- The user has commits on a feature branch and wants to open a PR against another branch.

## Do not invoke when

- The user only wants a diff summary or a description draft *without* opening a PR (use a plain message instead).
- The current branch has no commits ahead of the target branch.
- The user is asking for a rebase, squash, force-push, or branch cleanup — not a PR.
- The user has already written the title + body themselves and just wants you to run `gh pr create` verbatim.

---

## Workflow

### Step 1 — Preconditions + target branch

Run these checks in parallel:

- `git rev-parse --is-inside-work-tree` — must be a git repo.
- `gh auth status` — must be authenticated; if not, surface the failure verbatim and stop.
- `git rev-parse --abbrev-ref HEAD` — capture the current (head) branch.

Resolve the **target branch** in this priority order:

1. The skill argument (e.g. `/create-pr develop`).
2. A branch name explicitly stated in the user's invocation message.
3. If neither: **halt and ask the user for the target branch.** Do not offer suggestions, defaults, or auto-detected candidates. Do not pre-fill from the repo's default branch. The user must type or paste the branch name.

Validate the supplied target: `git ls-remote --heads origin <target>` must return a result. If not, stop and report.

The head branch must not equal the target branch — if it does, stop and report.

### Step 2 — Gather branch context

Run in parallel after target is set:

- `git fetch origin <target>` — make sure the base is current.
- `git log <target>..HEAD --pretty=format:'%h %s%n%b'` — full commit messages.
- `git diff <target>...HEAD --stat` — file change summary.
- `git diff <target>...HEAD` — the actual diff. For very large diffs, read the stat plus the first ~200 lines of hunks.
- `git status` — flag uncommitted or untracked files; ask the user whether to commit them before continuing.
- `git rev-parse --abbrev-ref --symbolic-full-name @{u}` — detect whether the branch has an upstream (handle the "no upstream" error).

### Step 3 — Detect existing PR template

Check these paths in order, stopping at the first match:

1. `.github/PULL_REQUEST_TEMPLATE.md`
2. `.github/pull_request_template.md`
3. `docs/pull_request_template.md`
4. `pull_request_template.md` at the repo root.
5. Any `**/pull_request_template.md` (monorepos may place one per service).

If found: read it. Treat its headings as the required structure. Preserve checkboxes and instructional comments verbatim. Match the template's language when drafting (e.g. Portuguese template → Portuguese body).

If not found: use the default three-section body in Step 6.

### Step 4 — Check for an existing PR

`gh pr list --head <head-branch> --json number,url,title,body`

If a PR already exists for this branch: ask the user whether to **update** it (Step 8 uses `gh pr edit`) instead of creating a duplicate. Never open a second PR for the same branch silently.

### Step 5 — Classify the change + check for ambiguity

Classify the dominant nature of the change from commit messages + diff: feat / fix / refactor / docs / test / chore / perf / build / ci.

Look for multi-purpose branches — two or more unrelated commit clusters (e.g. a refactor commit plus an unrelated feature commit plus a docs commit). If detected, **surface the ambiguity to the user**: list each cluster in one or two sentences and ask whether to (a) describe them as one PR with multiple sections, (b) split the branch into multiple PRs, or (c) describe only one cluster and exclude the rest. Do not guess.

Also sample the repo's title style: `gh pr list --state merged --limit 10 --json title`. Detect whether titles use Conventional Commits (`feat:`, `fix:`...) or plain imperative style, and whether they use emoji. Mirror that style.

### Step 6 — Draft the title and body

**Title:**

- Imperative mood, ≤ 70 characters, no trailing period.
- Follow the repo's title style detected in Step 5 (Conventional Commits, emoji, etc.).
- No marketing words. See anti-patterns.

**Body — template path:** if a template was detected in Step 3, fill each section, keep instructional comments intact, match the template's language.

**Body — default path** (no template), three sections:

```markdown
## Purpose
1–3 sentences on *why* this change exists. State the problem or the goal,
not the implementation.

## Summary
- Grouped bullets describing what changed (not file-by-file diff restatement).
- One bullet per logical change cluster.

## Test plan
- Concrete commands or steps used to verify (e.g. `npm test -- cart.test.ts`).
- If no automated tests were added, say so honestly:
  "Manual: ran `<command>` against staging and confirmed `<observable>`."
```

Target ≤ 250 words. Hard stop at 400. Every claim must be traceable to the diff or commits — do not invent rationale.

### Step 7 — Present for review

Print the drafted title + body to the user. Wait for explicit approval or edits. Do not call `gh pr create` (or `gh pr edit`) without the user's confirmation.

### Step 8 — Open or update the PR

If the branch is unpushed: ask the user before running `git push -u origin <head-branch>`.

For a new PR:

```bash
gh pr create --base <target> --head <head> --title "<title>" --body "$(cat <<'EOF'
<body>
EOF
)"
```

For an update path (from Step 4):

```bash
gh pr edit <number> --body "$(cat <<'EOF'
<body>
EOF
)"
```

Print the returned PR URL.

---

## Description structure rules (summary)

| Aspect | Rule |
|---|---|
| Title length | ≤ 70 chars |
| Title style | Imperative, no trailing period, match repo style |
| Body length | ≤ 250 words target, 400 hard cap |
| Required first section | Purpose (or template equivalent) |
| Default sections | Purpose / Summary / Test plan |
| Template detection | 5 paths checked, instructions preserved |
| Language | Match template language; otherwise repo default |

---

## Silent quality checklist (run before showing the draft)

1. Title ≤ 70 chars, imperative mood, no trailing period.
2. Body opens with Purpose stated in ≤ 3 sentences (or the template's first section equivalent).
3. Body ≤ 250 words (soft) / 400 (hard).
4. No anti-patterns from the list below.
5. If a template was detected, every required section is filled and instructional comments are preserved.
6. Language matches the template (or repo default if no template).
7. Test plan lists concrete commands, or honestly says "manual verification only".
8. No invented paths, function names, or rationale — every claim traceable to diff / commits.
9. No `Co-Authored-By: Claude` trailer in the PR body (commits already carry it).
10. Target branch was explicitly supplied or confirmed by the user.

If any item fails, fix the draft before presenting.

---

## Anti-patterns

- Don't restate the diff line-by-line ("Changed `foo` to `bar` in file X, then changed `baz` to `qux` in file Y…"). Group by purpose.
- Don't use marketing language: "seamless", "robust", "amazing", "comprehensive overhaul", "best-in-class", "leverage".
- Don't add emoji unless the repo style already uses them.
- Don't pad with filler sentences like "This PR introduces changes that…" or "In summary, this PR…".
- Don't claim something was tested when no test code was added and no manual run happened.
- Don't invent rationale that isn't visible in the commits or diff — if the *why* is unclear, ask the user one targeted question rather than guessing.
- Don't add a `Co-Authored-By: Claude` trailer to the PR body. Commits already carry it.
- Don't auto-pick a target branch. Always require the user to supply or confirm one.

---

## Worked example

**Input:**
- Head branch: `fix/null-check-on-empty-cart`
- Target: `main` (passed as `/create-pr main`)
- 1 commit ahead: `Fix NPE when cart is empty during checkout`
- Diff: `src/checkout/cart.ts` (4 lines changed); `tests/checkout/cart.test.ts` (1 new test).
- No PR template detected.

**Emitted title:** `Fix NPE on empty cart during checkout`

**Emitted body:**

```markdown
## Purpose
Checkout crashed with a null pointer when the cart was emptied right before submit. This restores the guard so empty-cart submissions return the expected "cart is empty" message instead of a 500.

## Summary
- Add empty-array guard at the top of `submitCheckout` in `src/checkout/cart.ts`.
- Add a regression test covering the empty-cart path.

## Test plan
- `npm test -- cart.test.ts` passes the new case.
- Manual: emptied the cart in staging and confirmed the "cart is empty" message renders instead of a 500.
```

A longer multi-commit example with a Portuguese PR template lives in [references/examples.md](references/examples.md).

---

## Limits

- Detection of repo style (Conventional Commits, emoji, language) is sampled from the last ~10 merged PRs. Brand-new repos with no merged PRs fall back to plain imperative English.
- Very large diffs are summarized from `--stat` + the first hunks; the skill may miss subtle reasoning hidden deep in a 5000-line diff. Surface this to the user when it happens.
- The skill does not run repo tests, linters, or CI before opening the PR. The Test plan section is built from what the diff *shows* was tested, plus anything the user reports manually.
