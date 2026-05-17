#!/usr/bin/env bash
# PreToolUse hook for Edit/Write/NotebookEdit.
#
# Blocks the tool call (exit 2) when the user's working tree has
# pre-existing uncommitted changes that haven't been protected yet
# this session. On block, Claude reads stderr and invokes the
# `commit-before-changes` skill.
#
# On clean trees (or when the cwd is not a git repo) the hook creates
# a per-session marker so subsequent edits in the same session pass
# through immediately. This means: even if Claude's own edits make
# the tree dirty later in the session, the hook will NOT re-fire and
# block them.
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

MARKER="/tmp/.claude-cbc-${SESSION_ID}"

# --------------------------------------------------------------- fast path
# Marker already created -> tree was clean (or non-git) at first
# check this session. Allow.
if [ -f "$MARKER" ]; then
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
  # Clean tree -> mark and allow. From now on Claude's own edits
  # will make the tree dirty, but the marker keeps us from blocking
  # them.
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
[commit-before-changes] Working tree has pre-existing uncommitted changes.

Invoke the \`commit-before-changes\` skill to draft a commit message
(context-first: active plan → conversation → memory → diff fallback),
confirm with the user, and commit before this edit proceeds.

Current state (\`git status --short\`):
${PREVIEW}${EXTRA}

After the skill commits, retry the original tool call.
EOF

exit 2
