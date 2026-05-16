# MAP.md format

Every `MAP.md` follows this exact shape. The skill enforces ordering and length caps.

---

## Example — `src/utils/` (5 files, 2 subfolders)

````markdown
# src/utils — MAP

Purpose: Cross-cutting helpers used by feature modules — no business logic, no I/O.

## Files
- `dates.ts` — date parsing and formatting helpers (UTC-safe).
- `errors.ts` — shared error classes and the `toUserMessage` mapper.
- `logger.ts` — thin wrapper around pino; sets default fields.
- `result.ts` — `Result<T,E>` type and `ok`/`err` constructors.
- `strings.ts` — slugify, truncate, and case helpers.

## Subfolders
- `crypto/` — hashing and HMAC helpers; see `src/utils/crypto/MAP.md`.
- `testing/` — Jest matchers and fixture builders; see `src/utils/testing/MAP.md`.

<!-- preserve:start -->
<!-- Anything between these markers is kept on regeneration. -->
<!-- preserve:end -->

---
Generated: 2026-05-16 by codebase-map v1.0.0 — verify before trusting; run `/codebase-map ./src/utils` to refresh.
````

---

## Section order (mandatory)

1. **Title** — `# <folder-path-from-repo-root> — MAP`
2. **Purpose** — one sentence, after the title with a blank line.
3. **Files** — `## Files` heading + alphabetical list.
4. **Subfolders** — `## Subfolders` heading + alphabetical list. Omit the section entirely if there are no subfolders.
5. **Preserve block** — `<!-- preserve:start -->` / `<!-- preserve:end -->`, always present, even when empty (placeholder comment inside).
6. **Footer** — preceded by `---` separator, single line, format below.

---

## Length ceilings (hard)

- **Purpose line**: ≤ 160 chars, one sentence.
- **Entry text after the dash**: ≤ 100 chars. Truncate at 97 chars + `...` if longer.
- **Files section**: ≤ 40 entries. If more, replace the list with one summary line:
  `- (47 files; dominant: .ts (31), .test.ts (12), .css (4) — run \`ls\` to enumerate)`
- **Subfolders section**: ≤ 30 entries. Same overflow rule.

---

## Ordering rules

- Files: alphabetical, **case-insensitive**.
- Subfolders: alphabetical, **case-insensitive**.

Stable ordering keeps merge conflicts small and predictable.

---

## File entry conventions

- Wrap the filename in backticks: `` `name.ext` ``.
- The dash and one space, then the description.
- Describe **what the file is for** in plain terms. Not its API surface, not its line count.
- For files that are listed-but-not-read (lockfiles, minified, binaries), use a fixed tag:
  - `` `package-lock.json` `` — `dependency lockfile — do not edit.`
  - `` `bundle.min.js` `` — `minified build output — do not edit.`
  - `` `logo.png` `` — `binary asset.`

---

## Subfolder entry conventions

- Folder name with trailing slash in backticks: `` `crypto/` ``.
- Description is pulled from that subfolder's `Purpose:` line, truncated to ≤ 100 chars.
- Append a pointer: `; see \`<path>/MAP.md\`.`

If a subfolder has no `MAP.md` yet (first-run, processed after parent), write `(map pending)` as the description — the skill fills it on the same run when that subfolder's turn comes.

---

## Preserve block

Any text between `<!-- preserve:start -->` and `<!-- preserve:end -->` in a prior `MAP.md` is copied verbatim into the regenerated file. Use this for human notes the skill must not touch: folder-specific conventions, gotchas, links to deeper docs.

The skill always emits the markers, even when empty. Empty form:

```markdown
<!-- preserve:start -->
<!-- Anything between these markers is kept on regeneration. -->
<!-- preserve:end -->
```

---

## Footer

Single line, exact format:

```
Generated: YYYY-MM-DD by codebase-map vX.Y.Z — verify before trusting; run `/codebase-map <path>` to refresh.
```

- `YYYY-MM-DD` is today's date.
- `<path>` is the folder's path relative to the repo root.
- The skill parses `Generated:` on subsequent runs to drive the incremental refresh check.

---

## What does NOT belong in MAP.md

- Symbol-level detail (function lists, class hierarchies).
- API contracts, type signatures, parameter docs.
- Long prose explanations — those belong in `README.md`.
- Anything that would push the file beyond ~80 lines for typical folders.

If you find yourself wanting any of the above, write a separate doc and link to it from inside the preserve block.
