# commit-before-changes — commit message drafting rules

How to write the subject + body for the protection commit so it accurately reflects what is being saved.

---

## Source priority

Draft the message from the **first** source below that yields a faithful description of the dirty work. Don't skip ahead — earlier sources usually carry intent that the diff alone doesn't.

1. **Active plan file** in `~/.claude/plans/*.md` if one is being executed in this session. Read its `# Plan:` title and `## Context` section. Often the plan title is already a good subject.
2. **Session conversation context** — earlier user messages in this session. Look for phrases like "I was working on X", "before you start, I made some edits to Y", or any message naming a file that now appears in `git status`.
3. **Project-type auto-memory** — scan `~/.claude/projects/*/memory/MEMORY.md` for entries tagged `project` whose description mentions files/areas overlapping the diff. Only load the linked memory file if the index entry suggests a strong match.
4. **Git diff** — fallback. Inspect what's actually changed and describe it.

---

## Cross-check is mandatory

Whichever source you pick, **always** run:

```bash
git status --short
git diff --stat
```

…and verify the drafted message honestly describes the files actually touched. The message must be true about the diff, not just true about the user's intent.

---

## Divergence handling

If the source-derived message and the diff disagree (e.g. the plan says "refactor auth" but only `docs/setup.md` is dirty):

1. **Pick the message that fits the diff**, not the message that fits the source.
2. **Surface the divergence to the user** in the `AskUserQuestion` preview, e.g.:
   > "Note: the active plan is about auth, but the dirty files are in `docs/`. Drafting the commit message from the diff instead."

This lets the user catch the case where they forgot they had unrelated work in progress.

---

## Repo style detection

Run `git log --oneline -10` and classify:

| Pattern in recent commits | Style |
|---|---|
| `type(scope): subject` or `type: subject` (feat, fix, chore, etc.) | Conventional Commits — mirror it |
| `PROJ-123: subject` or `[PROJ-123] subject` | Ticket-prefixed — mirror it (try to find a ticket reference in the session context; otherwise drop the prefix and note "no ticket detected") |
| `Imperative subject.` (plain prose) | Plain imperative — mirror it |
| Mixed / no clear pattern | Default to plain imperative |

For Conventional Commits, pick the type from the diff:

| Diff content | Type |
|---|---|
| New feature, new file with new behavior | `feat` |
| Bug fix in existing behavior | `fix` |
| Internal restructuring without behavior change | `refactor` |
| Only docs/markdown/comments | `docs` |
| Only test files | `test` |
| Performance improvement | `perf` |
| Build/tooling/CI/deps | `chore` or `build` or `ci` |
| Whitespace / formatting only | `style` |

---

## Subject line rules

- Imperative mood: "Add X", "Fix Y", "Refactor Z" — not "Added X", not "Adding X".
- ≤ 70 characters.
- No trailing period.
- Capitalize the first word after any prefix (`feat: Add ...`, not `feat: add ...`) — unless the repo's convention says otherwise (sample `git log --oneline -10` to check).
- Be specific. `Update file` is no better than `wip`.

---

## Body rules

- **Only add a body** when the diff has multiple distinct concerns or one change needs context that won't fit in the subject.
- Bullets, not paragraphs. Wrap each line at 72 chars.
- One bullet per logical change cluster.
- Don't restate the diff line-by-line.

---

## Worked examples

Each example is labeled with the source that produced it.

### [from plan]

Active plan: `Add commit-before-changes skill + PreToolUse hook`.
Dirty files: `~/.claude/skills/commit-before-changes/SKILL.md` (new), `~/.claude/skills/.hooks/commit-before-changes.sh` (new).

> **Subject:** `Add commit-before-changes SKILL.md draft`

(Single concern, no body needed.)

### [from conversation]

Earlier in the session, user said: "I was finishing the install steps in the README before I asked you to help."
Dirty files: `README.md` only.

> **Subject:** `Update README install steps`

### [from memory]

`project` memory in MEMORY.md: "currently extracting auth middleware out of the main app per legal/compliance requirement".
Dirty files: `src/auth/middleware.ts` (new), `src/app.ts` (modified), `src/auth/index.ts` (modified).

> **Subject:** `Extract auth middleware into its own module`
>
> **Body:**
> - Move middleware logic from `src/app.ts` into new `src/auth/middleware.ts`
> - Re-export from `src/auth/index.ts`

### [from diff]

No active plan. No relevant conversation. No matching memory.
Dirty: untracked file `notes.md` containing meeting notes.

> **Subject:** `Add notes.md with team meeting notes`

### [divergence]

Active plan: `Refactor authentication flow`.
Dirty files: `docs/setup.md` only (no auth files touched).

> **Subject:** `Update setup documentation`
>
> *(In the AskUserQuestion preview, include the note: "The active plan is about auth, but only `docs/setup.md` is dirty. Drafted from the diff.")*

### [multi-concern fallback]

No plan, no conversation. Diff spans 3 unrelated files: a config tweak, a test fixture, and a typo fix in docs.

> **Subject:** `Save in-progress changes across config, tests, and docs`
>
> **Body:**
> - Tweak `config/dev.yml` log level to debug
> - Add fixture for empty-cart case in `tests/cart/fixtures.json`
> - Fix typo in `docs/install.md`

This is the one case where the subject must stay generic — but the body must still enumerate the real concerns. Never collapse a multi-concern message into `chore: save existing work`.

---

## Forbidden

These are never acceptable subjects, regardless of source:

- `chore: save existing work before new changes`
- `wip`
- `tmp`
- `save`
- `update`
- `changes`
- `progress`
- Any other content-free placeholder.

The whole point of this skill is fidelity to the work. A generic subject makes the protection commit useless for review and revert later.
