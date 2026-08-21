#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TARGET_ROOT="${HOME}/Library/Application Support/RonaldinhoPet"
CONFIGURATOR="$(mktemp "${TMPDIR:-/tmp}/ronaldinho-configure.XXXXXX")"
trap 'rm -f "$CONFIGURATOR"' EXIT

SDK_PATH="$(xcrun --show-sdk-path)"
SDK_VERSION="$(xcrun --show-sdk-version)"
swiftc -sdk "$SDK_PATH" -target "$(uname -m)-apple-macosx${SDK_VERSION}" \
  "$ROOT/RonaldinhoPet/configure-hooks.swift" -o "$CONFIGURATOR"
"$CONFIGURATOR" "$TARGET_ROOT" claude remove
"$CONFIGURATOR" "$TARGET_ROOT" codex remove

if [ -d "$TARGET_ROOT" ]; then
  pkill -f "$TARGET_ROOT/RonaldinhoPet.app/Contents/MacOS/RonaldinhoPet" 2>/dev/null || true
  mkdir -p "${HOME}/.Trash"
  mv "$TARGET_ROOT" "${HOME}/.Trash/RonaldinhoPet-$(date +%Y%m%d-%H%M%S)"
  echo "Moved the app and local state to Trash."
fi
if [ -d "${HOME}/.codex/pets/ronaldinho-gaucho" ]; then
  mkdir -p "${HOME}/.Trash"
  mv "${HOME}/.codex/pets/ronaldinho-gaucho" "${HOME}/.Trash/ronaldinho-gaucho-$(date +%Y%m%d-%H%M%S)"
fi
echo "Ronaldinho Pet uninstalled. Restart Claude Code/Desktop to reload hooks."
