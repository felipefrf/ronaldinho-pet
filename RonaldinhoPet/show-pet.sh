#!/bin/zsh
set -euo pipefail

COMPANION_DIR="${HOME}/Library/Application Support/RonaldinhoPet"
APP_PATH="${COMPANION_DIR}/RonaldinhoPet.app"
PROCESS_PATH="${APP_PATH}/Contents/MacOS/RonaldinhoPet"

if [ ! -x "$PROCESS_PATH" ]; then
  echo "Ronaldinho companion is not installed at ${COMPANION_DIR}." >&2
  exit 1
fi

if ! pgrep -f "$PROCESS_PATH" >/dev/null; then
  open -a "$APP_PATH"
fi

echo "Ronaldinho companion is ready."
