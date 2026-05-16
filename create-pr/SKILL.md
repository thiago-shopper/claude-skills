---
name: create-pr
description: |
  Use this skill when the user wants to open a GitHub pull request from the
  current branch. Trigger phrases: "create a PR", "open a pull request",
  "/create-pr", "ship this branch", "make a PR". Before opening the PR the
  skill triages any uncommitted changes and bumps the project version
  (package.json / pyproject.toml / setup.py / VERSION), proposing major /
  minor / patch from commit signals and asking the user to confirm.
  Produces a concise, objective title + body (Purpose / Summary / Test
  plan, or the repo's own template if one is present) and opens the PR via
  `gh pr create`. The user MUST specify the target/base branch — the
  skill never auto-picks one. If no target is supplied, the skill halts
  and asks (no suggestions, no defaults). Also detects an existing open
  PR for the branch and offers to update its body instead of creating a
  duplicate.
version: 1.1.0
allowed-tools: [Bash, Read, Edit, Write, AskUserQuestion]
argument-hint: <target branch> [optional PR notes]
---

# create-pr

Turn the current branch into a pull request whose description is **objective and concise** — it states the *why*, summarizes the change in grouped bullets, and lists a real test plan. Before opening, the skill triages pending changes and bumps the project version with the user's confirmation. Honors any repo-local PR template. Never auto-picks the target branch.

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

### Step 2 — Pending-change triage

Run `git status --porcelain`. If output is empty, skip to Step 3.

Otherwise, show the user a short summary (counts of modified / added / deleted / untracked files; first ~10 paths) and prompt via `AskUserQuestion`:

- **Commit pending changes together with the version bump** *(recommended when the diff is small and on-topic for the PR).*
- **Commit pending changes now as a separate commit, then bump version in its own commit.**
- **Abort — I'll clean up the working tree first.**

If "abort": stop the skill cleanly without staging or committing anything.

If "together": remember this choice for Step 4 (one combined commit).

If "split": remember this choice for Step 4 (two commits — pending first, then bump).

### Step 3 — Manifest detection + bump-level proposal

**Detect manifests.** Search non-recursively at repo root, plus `packages/*/` and `apps/*/` for monorepos. Collect every match:

- `package.json`
- `pyproject.toml`
- `setup.py`
- `VERSION`

For each, parse the current version. If parsing fails, surface the error and abort.

**If zero manifests are found:** prompt via `AskUserQuestion` — supply a manifest path / skip bump and continue to PR / abort.

**If more than one manifest is found:** show the list with each manifest's current version. Default-select the manifests whose directories have changes in `<target>..HEAD`. Prompt (multi-select): which manifests to bump. Allow override to "all".

**Propose a bump level.** Compute from commits in `<target>..HEAD`:

| Primary signal (commit messages) | Proposed level |
|---|---|
| Any `BREAKING CHANGE:` footer, or type with `!` (e.g. `feat!:`, `refactor!:`) | major |
| Any `feat:` commit | minor |
| Only `fix:` / `perf:` / `refactor:` / `docs:` / `test:` / `chore:` / `build:` / `ci:` / `style:` | patch |
| No conventional-commit syntax | patch (with a note) |

**Secondary signals** (advisory only — they never auto-promote tier; they only appear in the rationale line shown to the user):

- Removed exported symbols, removed public CLI flags, removed columns, removed routes → "possible breaking change".
- New exported symbols / new public functions → reinforces minor.

**Pre-release suffixes** (e.g. `1.2.3-rc.1`): prompt — drop suffix and bump core / keep suffix and bump core / abort.

**Confirm.** Prompt via `AskUserQuestion` with a one-line rationale (e.g. "Branch contains `feat!:` commit → major"). Options:

- **Apply major → `X.0.0`** *(Recommended if major proposed)*
- **Apply minor → `x.Y.0`** *(Recommended if minor proposed)*
- **Apply patch → `x.y.Z`** *(Recommended if patch proposed)*
- **Skip bump and continue to PR**
- **Abort**

Compute the next version by parsing current `MAJOR.MINOR.PATCH` from each selected manifest. If multiple manifests have different current versions, ask whether to advance each to its own next version or to a shared target version.

### Step 4 — Apply bump + commit

If "skip bump" was chosen in Step 3, run only the pending-change commit (if any from Step 2) and proceed to Step 5.

**Edit selected manifests.** See [references/version-bump.md](references/version-bump.md) for per-ecosystem field locations, lockfile handling, and parser caveats. Edits must be structured (parse → mutate → write); the one regex case is `setup.py`.

**Lockfiles:** `package-lock.json` gets its top-level `"version"` and root `""` entry under `"packages"` updated in place; **do not** run `npm install`. If `yarn.lock` or `pnpm-lock.yaml` is present, warn that the lockfile version won't be touched and ask: proceed without lockfile update / abort.

**Commit.** Use `AskUserQuestion` to confirm the commit message, pre-filled per the Step 2 choice:

- "together" path → `chore(release): <one-line summary of pending changes> + bump to vX.Y.Z`
- "split" path → first commit pending with `chore: <user summary>`; then second commit with `chore(release): bump version to vX.Y.Z`

Stage only the manifest/lockfile files for the bump commit; for "together", stage everything. Run `git commit` once per commit.

**If a pre-commit hook fails:** surface its output verbatim, do **not** retry with `--no-verify`, do **not** amend. Tell the user what to fix and abort the skill. Do not leave staged-but-uncommitted state — run `git reset HEAD` to unstage, but only if the user agrees.

### Step 5 — Gather branch context

Run in parallel:

- `git fetch origin <target>` — make sure the base is current.
- `git log <target>..HEAD --pretty=format:'%h %s%n%b'` — full commit messages (now including the bump commit).
- `git diff <target>...HEAD --stat` — file change summary.
- `git diff <target>...HEAD` — the actual diff. For very large diffs, read the stat plus the first ~200 lines of hunks.
- `git rev-parse --abbrev-ref --symbolic-full-name @{u}` — detect whether the branch has an upstream (handle the "no upstream" error).

### Step 6 — Detect existing PR template

Check these paths in order, stopping at the first match:

1. `.github/PULL_REQUEST_TEMPLATE.md`
2. `.github/pull_request_template.md`
3. `docs/pull_request_template.md`
4. `pull_request_template.md` at the repo root.
5. Any `**/pull_request_template.md` (monorepos may place one per service).

If found: read it. Treat its headings as the required structure. Preserve checkboxes and instructional comments verbatim. Match the template's language when drafting (e.g. Portuguese template → Portuguese body).

If not found: use the default three-section body in Step 9.

### Step 7 — Check for an existing PR

`gh pr list --head <head-branch> --json number,url,title,body`

If a PR already exists for this branch: ask the user whether to **update** it (Step 11 uses `gh pr edit`) instead of creating a duplicate. Never open a second PR for the same branch silently.

### Step 8 — Classify the change + check for ambiguity

Classify the dominant nature of the change from commit messages + diff: feat / fix / refactor / docs / test / chore / perf / build / ci. The bump commit from Step 4 is **excluded** from the classification (it's mechanical, not the PR's substance).

Look for multi-purpose branches — two or more unrelated commit clusters. If detected, **surface the ambiguity to the user**: list each cluster in one or two sentences and ask whether to (a) describe them as one PR with multiple sections, (b) split the branch into multiple PRs, or (c) describe only one cluster and exclude the rest. Do not guess.

Also sample the repo's title style: `gh pr list --state merged --limit 10 --json title`. Detect whether titles use Conventional Commits (`feat:`, `fix:`...) or plain imperative style, and whether they use emoji. Mirror that style.

### Step 9 — Draft the title and body

**Title:**

- Imperative mood, ≤ 70 characters, no trailing period.
- Follow the repo's title style detected in Step 8 (Conventional Commits, emoji, etc.).
- No marketing words. See anti-patterns.

**Body — template path:** if a template was detected in Step 6, fill each section, keep instructional comments intact, match the template's language.

**Body — default path** (no template), three sections; when a version bump was applied in Step 4, add a one-line `**Version:** vX.Y.Z` directly under the Purpose heading:

```markdown
## Purpose
**Version:** vX.Y.Z  <!-- only when a bump was applied -->

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

### Step 10 — Present for review

Print the drafted title + body to the user, plus the bump that was applied (or skipped) and the commits that were created in Step 4. Wait for explicit approval or edits. Do not call `gh pr create` (or `gh pr edit`) without the user's confirmation.

### Step 11 — Open or update the PR

If the branch is unpushed: ask the user before running `git push -u origin <head-branch>`.

For a new PR:

```bash
gh pr create --base <target> --head <head> --title "<title>" --body "$(cat <<'EOF'
<body>
EOF
)"
```

For an update path (from Step 7):

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
| Version line | One line under Purpose when a bump was applied |
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
11. If a version bump was applied, the `Version:` line under Purpose matches the bump commit.

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
- Don't bump the version without showing the user the proposed level and rationale and getting explicit confirmation.
- Don't auto-promote a major bump from diff signals alone — major requires a commit-message signal (`BREAKING CHANGE:` or `!`).
- Don't run `npm install` / `poetry lock` / equivalent during the bump. Edit manifests and lockfiles in place; warn the user if a real install would be needed.
- Don't skip pre-commit hooks (`--no-verify`) when the bump commit fails. Surface the error and stop.

---

## Worked example

**Input:**
- Head branch: `feat/empty-cart-message`
- Target: `main` (passed as `/create-pr main`)
- 2 commits ahead:
  - `feat: show explicit message when cart is empty`
  - `fix: guard against null cart in submitCheckout`
- Diff: `src/checkout/cart.ts` (12 lines changed); `tests/checkout/cart.test.ts` (2 new tests); `src/ui/EmptyCart.tsx` (new).
- Working tree clean. `package.json` present, current version `0.4.2`.
- No PR template detected.

**Step 2:** working tree clean → skip.

**Step 3:** detected `package.json` (single manifest). Primary signal: branch contains a `feat:` commit → **proposed: minor**. No `BREAKING CHANGE:` / `!`. User confirms minor.

**Step 4:** bumps `package.json` from `0.4.2` → `0.5.0`, plus matching entry in `package-lock.json`. Single commit: `chore(release): bump version to v0.5.0`.

**Emitted title:** `Show explicit message on empty cart`

**Emitted body:**

```markdown
## Purpose
**Version:** v0.5.0

Submitting checkout with an empty cart previously returned a 500 from a null
dereference. Users now see an explicit "cart is empty" message and the
backend path is guarded.

## Summary
- Add `EmptyCart` component and wire it into the checkout flow.
- Guard `submitCheckout` against a null/empty cart in `src/checkout/cart.ts`.
- Add two regression tests for the empty-cart path.

## Test plan
- `npm test -- cart.test.ts` covers the new cases.
- Manual: emptied the cart in staging and confirmed the new message renders instead of a 500.
```

A longer multi-commit example with a Portuguese PR template lives in [references/examples.md](references/examples.md). Detailed per-ecosystem bump rules and the full failure-mode table live in [references/version-bump.md](references/version-bump.md).

---

## Limits

- Detection of repo style (Conventional Commits, emoji, language) is sampled from the last ~10 merged PRs. Brand-new repos with no merged PRs fall back to plain imperative English.
- Very large diffs are summarized from `--stat` + the first hunks; the skill may miss subtle reasoning hidden deep in a 5000-line diff. Surface this to the user when it happens.
- The skill does not run repo tests, linters, or CI before opening the PR. The Test plan section is built from what the diff *shows* was tested, plus anything the user reports manually.
- Manifest detection is non-recursive at repo root plus `packages/*/` and `apps/*/`. Deeper or non-standard monorepo layouts require the user to point at the manifest path manually.
- Auto-detection of bump level is primarily commit-message-driven. Branches with non-conventional commits will default to patch — override at the confirm prompt when needed.
