#!/bin/zsh
set -euo pipefail

COMPANION_DIR="${HOME}/.claude/ronaldinho-pet"
STATE_TOOL="${COMPANION_DIR}/RonaldinhoClaudePet.app/Contents/Resources/RonaldinhoPetState"

if [ ! -x "$STATE_TOOL" ]; then
  echo "Ronaldinho companion state helper is not installed." >&2
  exit 1
fi

exec "$STATE_TOOL" update "$@"
