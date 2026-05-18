#!/usr/bin/env bash
# PreToolUse hook for Edit/Write/NotebookEdit.
#
# Blocks the tool call (exit 2) when the user's working tree has
# pre-existing uncommitted changes that haven't been acknowledged yet
# this session. On block, Claude reads stderr and invokes the
# `warn-before-changes` skill to show the dirty state to the user and
# get explicit permission to proceed. The skill never commits.
#
# Two markers govern allow vs. block:
#   /tmp/.claude-wbc-${SESSION_ID}        persistent — set by hook on
#                                         clean trees, and by the skill
#                                         when the user picks "Proceed
#                                         for session". Once set, the
#                                         hook stops blocking for the
#                                         rest of this session.
#   /tmp/.claude-wbc-once-${SESSION_ID}   one-shot — set by the skill
#                                         when the user picks "Proceed
#                                         once". The hook consumes (and
#                                         deletes) it on the next
#                                         invocation, so the *next*
#                                         edit re-warns.
#
# Hook contract:
#   exit 0  -> allow tool call
#   exit 2  -> block tool call (stderr -> Claude)
#   other   -> warning to user, does NOT block

set -u

# ---------------------------------------------------------------- input
# Read the entire JSON event from stdin. PreToolUse payload includes
# session_id, cwd, tool_name, tool_input, transcript_path.
INPUT="$(cat)"

# Extract session_id and cwd with python3 (jq not installed on this
# host; python3 ships in the base OS).
SESSION_ID="$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin).get("session_id", ""))
except Exception:
    print("")
' 2>/dev/null)"

CWD="$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin).get("cwd", ""))
except Exception:
    print("")
' 2>/dev/null)"

# Fall back to PWD if cwd is missing or empty.
[ -z "${CWD}" ] && CWD="$PWD"

# Fall back to a stable string if session_id is missing — this just
# means one shared marker rather than one per session, which is still
# safe.
[ -z "${SESSION_ID}" ] && SESSION_ID="unknown"

MARKER="/tmp/.claude-wbc-${SESSION_ID}"
ONCE_MARKER="/tmp/.claude-wbc-once-${SESSION_ID}"

# --------------------------------------------------------------- fast path
# Persistent session marker exists -> tree was clean (or non-git) at
# first check this session, OR the user already chose "Proceed for
# session". Allow.
if [ -f "$MARKER" ]; then
  exit 0
fi

# One-shot marker exists -> user chose "Proceed once" in the skill.
# Consume it (delete) so the next edit re-warns, then allow this edit.
if [ -f "$ONCE_MARKER" ]; then
  rm -f "$ONCE_MARKER" 2>/dev/null || true
  exit 0
fi

# --------------------------------------------------------------- git checks
cd "$CWD" 2>/dev/null || {
  # Can't even cd to the cwd. Don't block edits over a phantom path.
  : > "$MARKER" 2>/dev/null || true
  exit 0
}

# Not a git repo -> nothing to protect. Mark and allow.
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  date -u +%Y-%m-%dT%H:%M:%SZ > "$MARKER" 2>/dev/null || true
  exit 0
fi

# Inside a repo. Check working tree state.
STATUS="$(git status --porcelain 2>/dev/null || true)"

if [ -z "$STATUS" ]; then
  # Clean tree -> mark and allow. From now on Claude's own edits will
  # make the tree dirty, but the marker keeps us from blocking them.
  date -u +%Y-%m-%dT%H:%M:%SZ > "$MARKER" 2>/dev/null || true
  exit 0
fi

# --------------------------------------------------------------- block
# Dirty tree. Tell Claude to invoke the skill before editing.
# stderr is delivered to Claude on exit 2.

# Truncate the status preview so we don't flood the message — show
# the first 20 lines.
PREVIEW="$(printf '%s\n' "$STATUS" | head -n 20)"
EXTRA=""
if [ "$(printf '%s\n' "$STATUS" | wc -l)" -gt 20 ]; then
  EXTRA=$'\n  ...(truncated)'
fi

cat >&2 <<EOF
[warn-before-changes] Working tree has pre-existing uncommitted changes.

Invoke the \`warn-before-changes\` skill to show the user the current
dirty state and get explicit permission before this edit proceeds.
The skill does NOT commit anything — if the user wants to save their
work first, suggest \`/write-commit-message\`.

Session id (use this for marker filenames): ${SESSION_ID}

Current state (\`git status --short\`):
${PREVIEW}${EXTRA}

After the user picks "Proceed once" or "Proceed for session",
retry the original tool call.
EOF

exit 2
