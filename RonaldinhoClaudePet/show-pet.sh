#!/bin/zsh
set -euo pipefail

COMPANION_DIR="${HOME}/.claude/ronaldinho-pet"
APP_PATH="${COMPANION_DIR}/RonaldinhoClaudePet.app"
STATE_TOOL="${COMPANION_DIR}/update-state.sh"
PROCESS_PATH="${APP_PATH}/Contents/MacOS/RonaldinhoClaudePet"
SHOW_NONCE="$(date +%s)-$$"

if [ ! -x "$STATE_TOOL" ] || [ ! -d "$APP_PATH" ]; then
  echo "Ronaldinho companion is not installed at ${COMPANION_DIR}." >&2
  exit 1
fi

"$STATE_TOOL" idle "Ready — click to return" "$SHOW_NONCE" false

if ! pgrep -f "$PROCESS_PATH" >/dev/null; then
  open -a "$APP_PATH"
fi

echo "Ronaldinho companion is ready."
