#!/bin/zsh
set -euo pipefail

APP_PATH="${HOME}/Library/Application Support/RonaldinhoPet/RonaldinhoPet.app"
if [ ! -x "$APP_PATH/Contents/MacOS/RonaldinhoPet" ] && [ -x "/Applications/RonaldinhoPet.app/Contents/MacOS/RonaldinhoPet" ]; then
  APP_PATH="/Applications/RonaldinhoPet.app"
fi

if [ ! -x "$APP_PATH/Contents/MacOS/RonaldinhoPet" ]; then
  echo "Player Companions is not installed." >&2
  exit 1
fi

/usr/bin/open -a "$APP_PATH"

echo "Player Companions is ready."
