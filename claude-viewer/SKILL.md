---
name: claude-viewer
description: |
  Use this skill when the user wants to browse, search, or visually inspect
  the `.claude/` folder of a project together with all `.md` files at the
  project root (README, ARCHITECTURE, docs/, etc.) through a web UI.
  Trigger phrases: "view my .claude files", "browse claude config",
  "visualize my docs", "/claude-viewer", "ver os arquivos .claude",
  "visualizar md do projeto".

  Generates a self-contained Docker Compose stack under
  `.claude/viewer/` that mounts the project root read-only and serves a
  categorized, searchable, live-reloading browser at `localhost:3000`.

  Scope of files exposed:
  - `.claude/**/*.md` and `.claude/**/*.json` (configs, plans, skills, agents)
  - `**/*.md` from the project root (README, CHANGELOG, docs/, packages/X/*.md)
  - Hardcoded excludes: `node_modules/`, `.git/`, `dist/`, `build/`, `.next/`,
    `.nuxt/`, `.venv/`, `venv/`, `target/`, `.cache/`, `coverage/`

  Do not invoke when:
  - The user wants to edit the files — this viewer is read-only.
  - The user wants a one-shot CLI listing — just answer in chat.
  - There is no `.claude/` folder and the user does not want to create one.
version: 0.1.0
allowed-tools: [Bash, Read, Write, AskUserQuestion]
argument-hint: <optional target dir, defaults to cwd>
---

# claude-viewer

Spin up a local, read-only, web-based browser for everything Claude knows
about a project. Read documentation, plans, agents, skills, and configs
without flipping editor tabs.

The stack is plain Node + Express + EJS + vanilla JS. No build step on
the frontend. Vendor JS/CSS for `marked` and `highlight.js` is copied
out of `node_modules/` during the image build, so the container runs
fully offline.

---

## When to use

- The user wants to **see** what's in `.claude/` (plans, skills, agents, settings).
- The user wants a **searchable index** of the project's documentation.
- The user explicitly invokes `/claude-viewer`.

## Do not invoke when

- The user wants to **edit** these files — open them in the editor instead.
- The user wants the viewer to mutate the project (write back, refactor).
- The project has no `.claude/` **and** the user does not want one created.

---

## Workflow

### Step 1 — Preflight

Run in parallel:
- `docker --version` — must succeed.
- `docker compose version` — must succeed (Compose v2 plugin form).
- `pwd` and `ls -A` — capture the target directory.

If `docker` or `docker compose` is missing, halt with a clear message
("install Docker Desktop / Docker Engine + Compose v2 plugin") and exit.
Do not attempt to install anything.

Resolve `TARGET_DIR`:
- If the user passed a directory as a skill argument and it exists, use it.
- Otherwise `pwd`.

### Step 2 — Detect `.claude/`

```bash
test -d "$TARGET_DIR/.claude"
```

- **Exists** → continue to Step 3.
- **Missing** → `AskUserQuestion`:
  - `Create empty .claude/` *(Recommended)* — `mkdir -p "$TARGET_DIR/.claude"` and continue.
  - `Abort` — print "Nothing to view without `.claude/`. Exiting." and stop.

### Step 3 — Detect existing `.claude/viewer/`

```bash
test -d "$TARGET_DIR/.claude/viewer"
```

If it exists, `AskUserQuestion` (3-way):
- `Reuse existing` *(Recommended)* — skip generation, jump to Step 7.
- `Overwrite` — proceed; each `Write` in Step 5 will replace files.
- `Abort` — print path and stop.

### Step 4 — Choose port

`AskUserQuestion`:
- `3000` *(Recommended)*
- `8080`
- `Other` — user types a value; validate it's a positive integer < 65536.

Remember as `PORT`.

### Step 5 — Generate the stack

`Write` each file in this order. Bodies live in
[references/file-templates.md](references/file-templates.md). The
templates use `{{PORT}}` as the only placeholder — substitute before
writing.

1. `.claude/viewer/.dockerignore`
2. `.claude/viewer/Dockerfile`
3. `.claude/viewer/docker-compose.yml`
4. `.claude/viewer/package.json`
5. `.claude/viewer/server.js`
6. `.claude/viewer/lib/scanner.js`
7. `.claude/viewer/lib/categorize.js`
8. `.claude/viewer/lib/search.js`
9. `.claude/viewer/lib/watcher.js`
10. `.claude/viewer/views/index.ejs`
11. `.claude/viewer/views/partials/sidebar.ejs`
12. `.claude/viewer/views/partials/topbar.ejs`
13. `.claude/viewer/public/style.css`
14. `.claude/viewer/public/app.js`
15. `.claude/viewer/README.md`

After all files are written, do NOT add anything to `.gitignore` —
the stack is meant to be committable if the team wants to share it.
If the user later wants to ignore it, they can add `.claude/viewer/`
themselves.

### Step 6 — Build the image

```bash
cd "$TARGET_DIR/.claude/viewer" && docker compose build
```

Expect ~30s on a cold cache. If the build fails:
- Print the last 40 lines of compose output.
- Halt. Do not retry automatically.

### Step 7 — Smoke test

```bash
cd "$TARGET_DIR/.claude/viewer" && docker compose up -d
sleep 2
curl -sf "http://localhost:${PORT}/healthz"
```

If the health check fails:
- `docker compose logs --tail 40`
- Print the logs and halt.

If the health check passes, leave the container running and continue.

### Step 8 — Final message

Print exactly:

```
✅ claude-viewer is running

   Open:    http://localhost:{{PORT}}
   Start:   cd .claude/viewer && docker compose up
   Stop:    cd .claude/viewer && docker compose down
   Logs:    cd .claude/viewer && docker compose logs -f
   Port:    edit PORT in .claude/viewer/docker-compose.yml
            (or: PORT=8081 docker compose up)
```

Do not offer follow-ups. The user can browse and stop on their own.

---

## API contract (for reference and debugging)

The server exposes:

| Method | Route | Returns |
|---|---|---|
| `GET /` | HTML shell (EJS) |
| `GET /api/tree` | `{ categories: [{ name, groups: [{ name, files: [{path,name,ext,size,mtime}] }] }] }` |
| `GET /api/file?path=...` | `{ path, ext, content, rendered }` |
| `GET /api/search?q=...` | `{ q, hits: [{ path, name, snippets: [{line,text,match:[s,e]}] }] }` |
| `GET /healthz` | `{ ok: true }` |
| `WS /ws` | `{ type:"change", path }` / `{ type:"ready" }` |

Categorization rules live in [references/categorize-spec.md](references/categorize-spec.md).

---

## Edge cases

- **`TARGET_DIR` is not a directory** → halt at Step 1 with "target not found".
- **Port already in use** → smoke test will fail; show the docker logs and tell
  the user to pick another port (re-run skill or edit compose).
- **Permission denied on `.claude/`** → halt; print the error verbatim. Do not
  attempt `chmod`.
- **User on rootless Docker / Podman** → if `docker compose version` returns
  Compose v1 or fails, halt with "needs Docker Compose v2".
- **Massive projects (lots of .md)** → no hard limit in v1; the scanner respects
  the excludes list. If the tree call gets slow, the user can edit the excludes
  in `lib/scanner.js`.

---

## Anti-patterns

- Do not bake the project files into the image — always read from the mount.
- Do not write outside `.claude/viewer/` (no editing root files, no `.gitignore`
  mutation).
- Do not enable any kind of write API. The mount is read-only on purpose.
- Do not expose the server on `0.0.0.0` outside the container — `docker-compose.yml`
  binds to localhost via the host port mapping default.
- Do not auto-open the browser. Just print the URL.
