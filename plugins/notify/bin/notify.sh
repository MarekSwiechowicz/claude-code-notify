#!/usr/bin/env bash
# Hook entry point (Stop / Notification): desktop notification that a Claude Code session
# is waiting for you. Finds node even outside PATH (hooks start with a trimmed environment).
# Always exits 0.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="$HOME/.claude/claude-notify.log"
NODE=""
for c in node "$HOME/.nvm/versions/node/"*/bin/node /opt/homebrew/bin/node /usr/local/bin/node "/c/Program Files/nodejs/node.exe"; do
  if command -v "$c" >/dev/null 2>&1; then NODE="$c"; break; fi
done
# Read stdin with a timeout: if the pipe were left open, node would hang until the hook
# timeout and the notification would never appear.
INPUT=""
IFS= read -r -t 2 -d '' INPUT || true
if [ -n "$NODE" ]; then
  printf '%s' "$INPUT" | "$NODE" "$DIR/notify.js" >/dev/null 2>>"$LOG"
elif command -v osascript >/dev/null 2>&1; then
  osascript -e 'display notification "Session is waiting for your input" with title "Claude Code" sound name "Glass"' >/dev/null 2>&1
elif command -v notify-send >/dev/null 2>&1; then
  notify-send --app-name="Claude Code" "Claude Code" "Session is waiting for your input" >/dev/null 2>&1
fi
exit 0
