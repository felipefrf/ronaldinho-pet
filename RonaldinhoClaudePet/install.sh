#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
ASSET_PATH="${ROOT}/spritesheet.webp"
COMPANION_DIR="${HOME}/.claude/ronaldinho-pet"
APP_SOURCE="${ROOT}/RonaldinhoClaudePet.app"
APP_TARGET="${COMPANION_DIR}/RonaldinhoClaudePet.app"
CONFIG_BINARY="${ROOT}/build/RonaldinhoConfigure"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Ronaldinho Claude companion is supported on macOS only." >&2
  exit 1
fi

if ! command -v swiftc >/dev/null 2>&1; then
  echo "Xcode Command Line Tools are required. Run: xcode-select --install" >&2
  exit 1
fi

if ! command -v claude >/dev/null 2>&1; then
  echo "Claude Code must be installed before the companion can be configured." >&2
  exit 1
fi

if [ ! -f "$ASSET_PATH" ]; then
  echo "Missing bundled spritesheet: $ASSET_PATH" >&2
  exit 1
fi

mkdir -p "${ROOT}/build"
"${ROOT}/build-app.sh" "$ASSET_PATH" >/dev/null
mkdir -p "$COMPANION_DIR"

for pid in $(pgrep -f "$APP_TARGET/Contents/MacOS/RonaldinhoClaudePet" || true); do
  process_info=$(ps -p "$pid" -o command=)
  case "$process_info" in
    "$APP_TARGET"/Contents/MacOS/RonaldinhoClaudePet) kill "$pid" ;;
    *) echo "Unexpected companion process: $process_info" >&2; exit 1 ;;
  esac
done

ditto "$APP_SOURCE" "$APP_TARGET"
ditto "${ROOT}/update-state.sh" "${COMPANION_DIR}/update-state.sh"
ditto "${ROOT}/acknowledge-state.sh" "${COMPANION_DIR}/acknowledge-state.sh"
ditto "${ROOT}/show-pet.sh" "${COMPANION_DIR}/show-pet.sh"
chmod +x "${COMPANION_DIR}/update-state.sh" "${COMPANION_DIR}/acknowledge-state.sh" "${COMPANION_DIR}/show-pet.sh"

SETTINGS_PATH="${HOME}/.claude/settings.json"
if [ -f "$SETTINGS_PATH" ]; then
  BACKUP_PATH="${HOME}/.claude/settings.json.ronaldinho-backup-$(date +%Y%m%d-%H%M%S)"
  cp "$SETTINGS_PATH" "$BACKUP_PATH"
fi

swiftc "${ROOT}/configure-claude.swift" -o "$CONFIG_BINARY"
"$CONFIG_BINARY" "$COMPANION_DIR"
"${COMPANION_DIR}/show-pet.sh"

echo "Ronaldinho is installed. Restart Claude Code, then run /pet any time you want to show him."
