# categorize-spec

Reference for the `categorize(relPath)` function in `lib/categorize.js`.

`relPath` is the path **relative to the project root** (the mount point
`/project` inside the container), using forward slashes. Returns
`{ category, group }` where `group` may be `null`.

---

## Rules in order

| # | Input pattern | Output `category` | Output `group` |
|---|---|---|---|
| 1 | `.claude/plans/**` | `Plans` | `null` |
| 2 | `.claude/skills/<slug>/**` | `Skills` | `<slug>` |
| 3 | `.claude/agents/**` | `Agents` | `null` |
| 4 | `.claude/commands/<slug>/**` | `Commands` | `<slug>` |
| 5 | `.claude/commands/*.md` (flat) | `Commands` | `null` |
| 6 | `.claude/hooks/**` or `.claude/.hooks/**` | `Hooks` | `null` |
| 7 | `.claude/memory/**` | `Memory` | `null` |
| 8 | `.claude/CLAUDE.md` | `Memory` | `.claude` |
| 9 | `.claude/settings.json`, `.claude/settings.local.json` | `Settings` | `.claude` |
| 10 | `.claude/mcp.json` | `MCP` | `null` |
| 11 | anything else under `.claude/<top>/...` | `.claude (other)` | `<top>` |
| 12 | `CLAUDE.md` (project root) | `Memory` | `null` |
| 13 | flat `*.md` at project root | `Project Docs` | `null` |
| 14 | `<top>/**/*.md` (anywhere else) | `Docs` | `<top>` |
| 15 | anything else | `Other` | `null` |

The function evaluates these in order — first match wins.

---

## Sidebar ordering

```
Memory
Project Docs
Docs
Settings
MCP
Plans
Skills
Agents
Commands
Hooks
.claude (other)
Other
```

Categories with zero files are omitted. Within a category, groups
sort alphabetically (`null` group renders flat under the category
header). Within a group, files sort by `name`.

---

## Worked examples

| `relPath` | `category` | `group` |
|---|---|---|
| `.claude/plans/2026-01-foo.md` | `Plans` | `null` |
| `.claude/skills/create-pr/SKILL.md` | `Skills` | `create-pr` |
| `.claude/skills/create-pr/references/style.md` | `Skills` | `create-pr` |
| `.claude/agents/code-reviewer.md` | `Agents` | `null` |
| `.claude/commands/deploy.md` | `Commands` | `null` |
| `.claude/commands/db/migrate.md` | `Commands` | `db` |
| `.claude/.hooks/push.sh.md` | `Hooks` | `null` |
| `.claude/memory/preferences.md` | `Memory` | `null` |
| `.claude/CLAUDE.md` | `Memory` | `.claude` |
| `.claude/settings.json` | `Settings` | `.claude` |
| `.claude/settings.local.json` | `Settings` | `.claude` |
| `.claude/mcp.json` | `MCP` | `null` |
| `.claude/weird/thing.md` | `.claude (other)` | `weird` |
| `CLAUDE.md` | `Memory` | `null` |
| `README.md` | `Project Docs` | `null` |
| `CHANGELOG.md` | `Project Docs` | `null` |
| `ARCHITECTURE.md` | `Project Docs` | `null` |
| `docs/api/auth.md` | `Docs` | `docs` |
| `packages/web/README.md` | `Docs` | `packages` |
| `apps/api/docs/setup.md` | `Docs` | `apps` |

---

## Edge cases

- **Case sensitivity** — `CLAUDE.md` regex uses `/i` to match `Claude.md`, `claude.md`. All other matches are case-sensitive.
- **Symlinks** — the scanner does not follow them. If chokidar fires on a symlink target, the path may not be in the allowlist; the API returns `404`.
- **Hidden files inside `.claude/`** — `.claude/.foo` is treated like any other entry. The categorization will fall through to rule 11 (`.claude (other)`).
- **File at `.claude/` root that isn't a special case** — e.g. `.claude/notes.md`. Falls through to rule 11 with `group = null` (because `parts[0]` would be the file's own name; `categorize.js` handles this by setting `group: top || null`).
- **Files outside the project root** — impossible by construction; the scanner only walks under `BASE`, and `/api/file` rejects paths outside.

---

## How to extend

To add a new category (say `Workspace` for `.claude/.shopper-workspace/`):

1. Add a rule above rule 11 in `lib/categorize.js`:
   ```js
   if (top === '.shopper-workspace') return { category: 'Workspace', group: null };
   ```
2. Insert `'Workspace'` into the `ORDER` array in `server.js` at the desired position.
3. No frontend change needed — the sidebar renders whatever the API returns.
