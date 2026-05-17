# Claude Code Skills

Personal collection of [Claude Code](https://docs.anthropic.com/claude/docs/claude-code) skills and hooks. Drop this repo into `~/.claude/skills/`, wire up two hook entries in `~/.claude/settings.json`, and Claude Code picks the skills up automatically on the next launch.

This repo augments Claude Code; it does not install it. Install Claude Code first.

---

## What's inside

### Skills

| Name | What it does | Invoked via |
|---|---|---|
| `codebase-map` | Generate or refresh per-folder `MAP.md` files for codebase navigation | `/codebase-map` |
| `commit-before-changes` | Pre-flight: commit pre-existing dirty work so Claude's edits don't tangle with yours | hook + `/commit-before-changes` |
| `create-pr` | Open a GitHub PR from the current branch, bump version, honor repo PR template | `/create-pr <target>` |
| `document-project` | Generate or refresh `README.md`, `CONTRIBUTING.md`, `ARCHITECTURE.md`, `DEPLOYMENT.md` | `/document-project` |
| `plan-mode-prompt` | Turn a vague idea into a Plan-Mode-ready prompt | `/plan-mode-prompt` |
| `project-starter` | Scaffold a new project (Backend API / CLI / Frontend / Fullstack / Monorepo / Library) from a short interview. Docker-first — never installs anything on the host. | `/project-starter` |

### Hooks

| File | Event | Purpose |
|---|---|---|
| `.hooks/commit-before-changes.sh` | `PreToolUse` on `Edit`/`Write`/`NotebookEdit` | Blocks the tool call if the working tree has unprotected pre-existing changes; points Claude at the `commit-before-changes` skill |
| `.hooks/push-skills.sh` | `Stop` | Auto-commits and pushes this repo at the end of every Claude session |

---

## Prerequisites

| Required for | Tool | Install |
|---|---|---|
| Everything | **Bash** (4+) | Pre-installed on Linux/macOS |
| Everything | **Git** | `apt install git` / `brew install git` |
| `commit-before-changes` hook | **Python 3** | Pre-installed on most distros; `brew install python3` on macOS |
| `create-pr` skill | **GitHub CLI (`gh`)** | <https://cli.github.com/> |
| `project-starter` skill | **Docker** + **Docker Compose v2** | <https://docs.docker.com/engine/install/> |
| Auto-push hook (optional) | SSH key with push access to your fork | `ssh-keygen` + `gh ssh-key add` |

`jq` is **not** required — JSON parsing uses Python 3.

---

## Quick start

### 1. Clone into the Claude Code skills directory

```bash
git clone https://github.com/thiago-shopper/claude-skills.git ~/.claude/skills
```

If you plan to use the auto-push hook, **fork first** and clone your fork — the hook pushes back to `origin`.

### 2. Wire the hooks

Add this block to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|NotebookEdit",
        "hooks": [
          { "type": "command", "command": "bash $HOME/.claude/skills/.hooks/commit-before-changes.sh" }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "*",
        "hooks": [
          { "type": "command", "command": "bash $HOME/.claude/skills/.hooks/push-skills.sh" }
        ]
      }
    ]
  }
}
```

If `settings.json` already has a `hooks` block, **merge** — don't overwrite. If the file doesn't exist yet, wrap the snippet above in `{ ... }`.

### 3. Restart Claude Code

Skills now appear in `/help` and as slash-commands (`/codebase-map`, `/create-pr`, etc.).

### 4. Sanity check

Inside any Claude Code session, run:

```
/status
```

The `Hooks` section should list both `commit-before-changes.sh` and `push-skills.sh`. If they're missing, re-check `~/.claude/settings.json`.

---

## Configuring the auto-push hook (`push-skills.sh`)

This hook runs at every Claude session's `Stop` event. It auto-commits changes to `~/.claude/skills/` and pushes them to `origin/main`. Useful if you treat this directory as a personal sync-across-machines repo.

The hook ships with a hardcoded SSH key path that almost certainly won't match yours. Pick one of two paths:

### Option A — Configure with your own SSH key (recommended)

Open `.hooks/push-skills.sh` and edit this line:

```bash
export GIT_SSH_COMMAND="ssh -i /var/home/shopper/core/ssh-keys/github-thiago-shopper"
```

Replace the path with your own key, e.g.:

```bash
export GIT_SSH_COMMAND="ssh -i $HOME/.ssh/id_ed25519"
```

Make sure the key is registered with your GitHub account:

```bash
gh ssh-key add ~/.ssh/id_ed25519.pub --title "claude-skills auto-push"
```

If you push to a non-`main` branch, also update the `BRANCH` variable near the top of the script.

### Option B — Disable the auto-push hook

Remove (or comment out) the `Stop` block in `~/.claude/settings.json`. The skills stay in place; you just won't get auto-commit + push at session end. You can always re-enable later.

---

## Configuring the PreToolUse hook (`commit-before-changes.sh`)

Runs before every `Edit`/`Write`/`NotebookEdit`. Detects pre-existing uncommitted changes and blocks the tool call until the `commit-before-changes` skill commits them. After the first clean check in a session, a marker is dropped at `/tmp/.claude-cbc-${session_id}` and the hook short-circuits to exit 0 on subsequent calls — so Claude's own edits later in the session don't trigger it.

The hook is self-contained (only needs `bash`, `git`, `python3`) and needs **no configuration**. To disable it, remove the `PreToolUse` block from `~/.claude/settings.json`.

---

## Per-skill notes

- **`create-pr`** — requires `gh auth login` to be set up; the skill calls `gh pr create` and `gh pr edit`. The skill never auto-picks a base branch — you must pass one (`/create-pr main`).
- **`commit-before-changes`** — requires `git config user.name` and `git config user.email` to be set (globally or per-repo). The skill refuses to commit otherwise and tells you which command to run.
- **`codebase-map`** — uses `git ls-files` to enumerate tracked files; needs no extra setup beyond a git repo.
- **`project-starter`** — requires Docker + Docker Compose v2. Deliberately does **not** require Node, Yarn, npm, or corepack on the host — everything runs inside containers.

`document-project` and `plan-mode-prompt` have no external dependencies beyond what Claude Code already provides.

---

## Layout

```
~/.claude/skills/
├── README.md                            (this file)
├── .gitignore
├── .hooks/
│   ├── commit-before-changes.sh         (PreToolUse hook)
│   └── push-skills.sh                   (Stop hook)
├── codebase-map/
│   ├── SKILL.md
│   └── references/
├── commit-before-changes/
│   ├── SKILL.md
│   └── references/
├── create-pr/
│   ├── SKILL.md
│   └── references/
├── document-project/
│   ├── SKILL.md
│   └── references/
├── plan-mode-prompt/
│   ├── SKILL.md
│   └── references/
└── project-starter/
    ├── SKILL.md
    └── references/
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Skills don't appear in `/help` | Repo cloned to wrong location | Must be at `~/.claude/skills/` exactly |
| Hooks not firing | `settings.json` block missing or malformed | Run `/status`, check the `Hooks` section; validate JSON with `python3 -m json.tool ~/.claude/settings.json` |
| `push-skills.sh: permission denied (publickey)` | SSH key path in script doesn't match your key, or key not registered with GitHub | See Option A above |
| `push-skills.sh: rebase against origin/main failed` | Local branch diverged from remote | Resolve manually with `cd ~/.claude/skills && git pull --rebase origin main` |
| `commit-before-changes` blocks every edit forever | Session marker not being created (e.g. `/tmp` not writable) | Check `/tmp/.claude-cbc-*` exists after first edit; if not, fix `/tmp` permissions |
| `/create-pr` fails with auth error | `gh` not authenticated | Run `gh auth login` |

---

## License / attribution

Personal repository, no formal license. Fork freely; don't expect support. Skill files are written for Claude Code by Anthropic and follow the conventions documented at <https://docs.anthropic.com/claude/docs/claude-code>.
