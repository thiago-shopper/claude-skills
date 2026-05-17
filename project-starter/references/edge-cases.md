# edge-cases

Recovery procedures for every situation the workflow can hit. Numbered to match the SKILL.md references (E1–E22).

The general rule: **surface what happened, do not auto-recover destructively, and never delete the user's work without explicit consent.**

---

## E1 — `./{{name}}` already exists and is non-empty

**Detection:** after Round 1, `ls -A ./{{name}}` returns at least one entry.

**Recovery:** `AskUserQuestion` with four options:

| Option | Action |
|---|---|
| Cancel (Recommended) | Stop the skill. Return to the parent flow. |
| Pick a different name | Re-prompt for the name (single-question `AskUserQuestion`). |
| Scaffold into `.` (only offered if `{{name}}` matches `basename "$(pwd)"`) | Treat the current directory as the target. Only safe when current dir is empty. |
| Overwrite | Confirm-double — show the existing top-level entries, ask again. Only after a second confirmation, proceed and silently overlay (no `rm -rf`). |

Never delete the existing contents. Overwriting means writing on top of them; collisions are surfaced per file.

---

## E2 — Project name has invalid chars

**Detection:** after Round 1, the name doesn't match `^[a-z][a-z0-9-]*[a-z0-9]$`.

**Recovery:** sanitize with this transform:
- Lowercase.
- Replace `[\s_]+` with `-`.
- Strip everything that isn't `[a-z0-9-]`.
- Collapse `-{2,}` to a single `-`.
- Trim leading/trailing `-`.

Show the user the original and the sanitized form. `AskUserQuestion`:

| Option | Action |
|---|---|
| Use the sanitized name (Recommended) | Continue with the sanitized form. |
| Type a different name | Re-prompt. |
| Cancel | Stop. |

If sanitization produces an empty string, skip to "Type a different name".

---

## E3 — Docker not installed

**Detection:** `docker --version` exits non-zero or returns "command not found".

**Recovery:** print this block and halt:

```
Docker is required for project-starter — it's how we avoid touching your host.

Install:
  Linux:   https://docs.docker.com/engine/install/
  macOS:   https://docs.docker.com/desktop/install/mac-install/
  Windows: https://docs.docker.com/desktop/install/windows-install/

Then re-run /project-starter.
```

Do **not** offer a host-yarn fallback. Docker is a hard requirement.

---

## E4 — Docker installed but daemon not running

**Detection:** `docker --version` succeeds but `docker info` fails.

**Recovery:**

```
Docker is installed but the daemon isn't running.

Linux (systemd):     systemctl --user start docker-desktop   # if using Docker Desktop
                  or sudo systemctl start docker             # if using Docker Engine
macOS / Windows:     open Docker Desktop
```

Halt.

---

## E5 — Docker Compose v1 (legacy `docker-compose` binary)

**Detection:** `docker compose version` fails *but* `docker-compose --version` succeeds.

**Recovery:**

```
You have the legacy `docker-compose` (v1). project-starter requires Compose v2.

Compose v2 ships as a Docker plugin (`docker compose`, no hyphen) and has
different YAML semantics that this skill relies on.

Install Compose v2:
  Linux: https://docs.docker.com/compose/install/linux/
  Docker Desktop already ships it on macOS/Windows.

Then re-run /project-starter.
```

Halt.

---

## E6 — Current directory is already inside a git repo

**Detection:** `git rev-parse --is-inside-work-tree` returns "true" before we `cd` into `./{{name}}`.

**Recovery:** ask the user:

| Option | Action |
|---|---|
| Treat the new project as its own repo (Recommended) | `cd ./{{name}} && git init` after scaffolding. |
| Share the parent repo (no `git init`) | Skip `git init`. The new files become part of the parent's working tree. |
| Cancel | Stop. |

Default to "treat as own repo" unless the user is in a workspace-style monorepo (heuristic: parent's `package.json` has a `workspaces` field). In that case default to "share parent".

---

## E7 — DB chosen, port collision on host

**Detection:** at scaffold time we can't detect this — the conflict happens at `docker compose up`, not at our verify step.

**Recovery:** in the **next-steps** block, add a note:

```
Note: this scaffold maps DB_PORT (default 3306 for MySQL, 5432 for Postgres) to the host.
If that port is already in use, edit docker-compose.yml under services.db.ports and change the host side:
  ports: ["13306:3306"]   # was 3306:3306
Then update .env's DB_PORT to match.
```

We do **not** probe the host for port availability — it's not the skill's job.

---

## E8 — Monorepo with zero starter packages

**Detection:** project type is Monorepo and the user hasn't been asked which packages to include.

**Recovery:** the skill silently generates one starter package at `packages/{{name}}-core/` using the Library template. Mention it in the next-steps block:

```
Generated one starter package at packages/{{name}}-core/. Add more apps under apps/
or more packages under packages/ as you go — re-run /project-starter to scaffold them.
```

---

## E9 — Ephemeral-container Vite bootstrap fails

**Detection:** the `docker run --rm node:20-alpine sh -c "corepack enable && yarn dlx create-vite@latest …"` invocation exits non-zero.

**Recovery:** surface the container's stderr **verbatim**. Then `AskUserQuestion`:

| Option | Action |
|---|---|
| Retry (Recommended) | Re-run the same command. Common when the failure was a transient registry hiccup. |
| Pin a different create-vite version | Ask which version, re-run with `yarn dlx create-vite@<version>`. |
| Cancel and clean up | `rm -rf ./{{name}}`. Confirm before deletion. |

**Never** fall back to handwriting Vite files. The skill's frontend branch *requires* the bootstrap to succeed.

---

## E10 — `docker compose build` fails after writes

**Detection:** Step 6 fails.

**Recovery:**
- Print the container output verbatim.
- Leave the partially-scaffolded directory in place. Do **not** auto-delete.
- Ask: retry build / cancel and leave / cancel and clean up (only with confirmation).

Most common cause: a typo in the generated Dockerfile or a missing dependency in the generated `package.json`. Either is a template bug — open an issue.

---

## E11 — Verify step (`yarn lint` / `yarn test` / `yarn build`) fails

**Detection:** Step 7 fails.

**Recovery:**
- Print the failing command's output verbatim.
- Stop. Do **not** retry. Do **not** edit files to "fix" it.
- Tell the user: "This is a project-starter template bug. Please file an issue at the skill repo with the verbatim output."

The scaffold is supposed to be green on first run. A failure here means the template has drifted from the actual ecosystem (e.g. a dependency version bump introduced a breaking change).

---

## E12 — User picks "Other" in the project-type question

**Detection:** Round 1 returns `Type = "Other"` (free-text answer).

**Recovery:**

```
project-starter supports six project types:

  1. Backend API
  2. CLI / script / job
  3. Frontend React app
  4. Fullstack app
  5. Monorepo
  6. Library / package

The free-text option isn't supported — pick one of the six, or run a one-off
scaffold outside the skill.
```

Re-prompt Round 1 (just the Type question) once. If the user picks "Other" again, halt.

---

## E13 — User cancels mid-flow after some files were written

**Detection:** any post-write failure or `Cancel` on the confirm question after Step 4.

**Recovery:**

| Option | Action |
|---|---|
| Keep the partial scaffold (Recommended) | Leave `./{{name}}` in place. Print what was written and what's still missing. |
| Delete `./{{name}}` | `rm -rf ./{{name}}` after a confirm-double. |

Default to keep. Never delete without two explicit confirmations.

---

## E14 — Library name collides with a published npm package

**Detection:** project type is Library and `publishConfig.access` is `"public"`. After scaffolding, run:
```
docker compose run --rm app yarn npm info {{name}} version
```

If that returns a version (i.e. the package exists), warn:

```
Note: the npm package "{{name}}" already exists (current version: x.y.z).
You won't be able to `yarn npm publish` to this name unless you own it.
Consider:
  - Renaming the package (edit package.json#name).
  - Publishing under a scope: @your-org/{{name}}.
  - Switching publish target to "Private registry" or "Local only".
```

The warning is **informational** — the scaffold still completes.

---

## E15 — App port (3000 / 5173) already in use on the host

**Detection:** same as E7 — we can't detect at scaffold time. Surfaces at `docker compose up`.

**Recovery:** next-steps block includes:

```
Note: the dev server listens on host port {{port}}. If it's busy, edit docker-compose.yml:
  ports: ["3001:3000"]   # remap to 3001
```

---

## E16 — Offline / Docker Hub unreachable

**Detection:** `docker compose build` fails with a network error pulling the base image.

**Recovery:** treat as E10. Most likely user is offline or behind a proxy.

If the user has a corporate proxy, suggest:
```
If you're behind a corporate proxy, configure Docker:
  ~/.docker/config.json:
  {
    "proxies": {
      "default": {
        "httpProxy": "http://proxy:port",
        "httpsProxy": "http://proxy:port"
      }
    }
  }
```

---

## E17 — MySQL (or Postgres) container fails to start

**Detection:** not part of the skill's verify step (verify only runs lint+test+build, none of which need the DB). Surfaces when the user runs `docker compose up`.

**Recovery:** next-steps block includes:

```
If the database container fails to start:
  - Check disk space: docker system df
  - Check RAM: MySQL 8 needs ~512MB minimum
  - Check the data volume: docker volume inspect {{name}}_dbdata
  - Reset the volume (DESTRUCTIVE): docker compose down -v && docker compose up
```

---

## E18 — `git config user.name` / `user.email` unset

**Detection:** at Step 5, before the initial commit, run:
```bash
git config user.name || echo MISSING
git config user.email || echo MISSING
```

If either is missing:

**Recovery:** skip the initial commit. Print:

```
Skipped the initial commit because git user.name / user.email is unset:

  git config --global user.name  "Your Name"
  git config --global user.email "you@example.com"

Then run:
  cd {{name}} && git add -A && git commit -m "chore: initial scaffold from project-starter"
```

Continue with the rest of the workflow.

---

## E19 — User re-runs the skill in the same parent directory

**Detection:** falls under E1 (the target dir already exists from a previous run).

**Recovery:** as per E1. Never silently overwrite.

---

## E20 — `yarn dlx create-vite` version drift

**Detection:** the ephemeral container succeeds but produces a tree that doesn't match what the overlay step expects (e.g. Vite renamed a file, changed its `tsconfig` shape, etc.).

**Recovery:** the overlay step is **resilient by design** — it only writes files it knows about and never reads Vite's output to make decisions (other than "did the directory get created"). If Vite's output drifts, the overlay still writes the same files.

If the overlay produces a project that fails verify (E11), pin the create-vite version in the next scaffold run:
- Edit `references/dependency-pins.md` (or this file) and update the create-vite pin.
- The skill's Vite bootstrap command becomes `yarn dlx create-vite@<pinned>`.

This is a **maintenance** edge case — surfacing it to the user is fine; the recovery is the maintainer's job.

---

## E21 — Host UID/GID mismatch (root-owned files)

**Detection:** at end of verify, `ls -la ./{{name}}/src` shows files owned by `root` instead of the host user.

**Prevention:** every service in every `docker-compose.yml` has:
```yaml
    user: "${UID:-1000}:${GID:-1000}"
```

**Recovery (if it still happens):** print:

```
Some files in ./{{name}} are owned by root because the container ran as root.

Fix (one-time):
  sudo chown -R "$USER:$USER" ./{{name}}

The compose file already sets `user: ${UID:-1000}:${GID:-1000}` — if this keeps
happening, export those vars in your shell:
  echo 'export UID="$(id -u)" GID="$(id -g)"' >> ~/.bashrc
```

---

## E22 — Bind-mounted `node_modules` clobbers container's install

**Detection:** `docker compose up` fails with "Cannot find module" errors after a successful build.

**Prevention:** every service in every `docker-compose.yml` has:
```yaml
    volumes:
      - .:/app
      - /app/node_modules    # anonymous volume — masks the host's empty node_modules
      - /app/.yarn/cache
```

The order matters: source bind first, then the anonymous volume for `node_modules`. Docker layers volumes top-down.

**Recovery (if it still happens):** print:

```
Looks like the container's node_modules got shadowed by an empty host folder.

Fix:
  docker compose down -v   # drops anonymous volumes too
  docker compose build
  docker compose up

If you see this every build, your docker-compose.yml is missing the
anonymous `/app/node_modules` volume line — check it.
```

---

## Cross-cutting rules

- **Never run `rm -rf` without a confirm-double.** Two questions, both default to "no".
- **Never run `--no-verify` on git commits.** If a pre-commit hook fails at Step 5, surface it and stop.
- **Never modify files outside `./{{name}}`.** The skill writes only into the target directory (plus, if Claude-wire=yes, the project's own `CLAUDE.md` and `.claude/settings.json` which live inside the target).
- **Never invoke `yarn`, `npm`, `node`, or `corepack` on the host.** All invocations go through `docker run` or `docker compose`. If you find yourself wanting to run a host command, stop and ask — there's probably a Dockerized equivalent.
