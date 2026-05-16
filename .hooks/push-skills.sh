#!/usr/bin/env bash
# Stop hook: auto-commit + push ~/.claude/skills/ to claude-skills.
# Idempotent. Errors visible via stderr + exit 1 (never exit 2 — that blocks Stop).

set -u
REPO="/var/home/shopper/.claude/skills"
BRANCH="main"

# Drain Claude Code's JSON payload from stdin so the script never blocks.
cat >/dev/null 2>&1 || true

# Not a git repo (user nuked .git/) -> silent no-op.
if [ ! -d "$REPO/.git" ]; then
  exit 0
fi

cd "$REPO" || exit 0

# Idempotency: no changes at all -> no-op.
if git diff --quiet \
   && git diff --cached --quiet \
   && [ -z "$(git ls-files --others --exclude-standard)" ]; then
  exit 0
fi

# Stage everything in the repo (the repo IS the skills tree).
git add -A || { echo "push-skills: git add failed" >&2; exit 1; }

# Bail if the stage ended up empty (e.g. mode-only churn).
if git diff --cached --quiet; then
  exit 0
fi

# Commit message: timestamp + list of touched top-level entries (skill names + .hooks).
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
CHANGED="$(git diff --cached --name-only \
  | awk -F/ '{print $1}' | sort -u | paste -sd, -)"
[ -z "$CHANGED" ] && CHANGED="(metadata)"
MSG="auto: update [${CHANGED}] @ ${TS}"

git commit -m "$MSG" || { echo "push-skills: git commit failed" >&2; exit 1; }

# Race safety: rebase on remote before pushing.
if ! git pull --rebase origin "$BRANCH" 2>/tmp/push-skills.rebase.err; then
  git rebase --abort 2>/dev/null || true
  echo "push-skills: rebase against origin/${BRANCH} failed. Commit kept locally; push skipped." >&2
  sed 's/^/push-skills:   /' /tmp/push-skills.rebase.err >&2
  exit 1
fi

if ! git push origin "$BRANCH" 2>/tmp/push-skills.push.err; then
  echo "push-skills: push to origin/${BRANCH} failed. Commit kept locally." >&2
  sed 's/^/push-skills:   /' /tmp/push-skills.push.err >&2
  exit 1
fi

echo "push-skills: pushed [${CHANGED}]"
exit 0
