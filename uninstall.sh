#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TARGET_ROOT="${HOME}/Library/Application Support/RonaldinhoPet"
CODEX_SKILL="${CODEX_HOME:-${HOME}/.codex}/skills/ronaldinho-pet"
CODEX_CREATOR_SKILL="${CODEX_HOME:-${HOME}/.codex}/skills/create-editable-pet"
TEMP_CONFIGURATOR=""
if [ -x "$TARGET_ROOT/RonaldinhoPet.app/Contents/Resources/RonaldinhoConfigureHooks" ]; then
  CONFIGURATOR="$TARGET_ROOT/RonaldinhoPet.app/Contents/Resources/RonaldinhoConfigureHooks"
elif [ -x "$ROOT/configure-hooks" ]; then
  CONFIGURATOR="$ROOT/configure-hooks"
elif [ -x "$ROOT/prebuilt/RonaldinhoPet.app/Contents/Resources/RonaldinhoConfigureHooks" ]; then
  CONFIGURATOR="$ROOT/prebuilt/RonaldinhoPet.app/Contents/Resources/RonaldinhoConfigureHooks"
else
  TEMP_CONFIGURATOR="$(mktemp "${TMPDIR:-/tmp}/ronaldinho-configure.XXXXXX")"
  CONFIGURATOR="$TEMP_CONFIGURATOR"
  SDK_PATH="$(xcrun --show-sdk-path)"
  CLANG_MODULE_CACHE_PATH="$(mktemp -d "${TMPDIR:-/tmp}/ronaldinho-module-cache.XXXXXX")"
  swiftc -sdk "$SDK_PATH" -target "$(uname -m)-apple-macosx${RONALDINHO_DEPLOYMENT_TARGET:-$(xcrun --show-sdk-version)}" -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
    "$ROOT/RonaldinhoPet/Host.swift" "$ROOT/RonaldinhoPet/configure-hooks.swift" -o "$CONFIGURATOR"
fi
trap 'if [ -n "$TEMP_CONFIGURATOR" ]; then rm -f "$TEMP_CONFIGURATOR"; rm -rf "$CLANG_MODULE_CACHE_PATH"; fi' EXIT
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
if [ -d "$CODEX_SKILL" ] && diff -qr "$ROOT/codex-skill/ronaldinho-pet" "$CODEX_SKILL" >/dev/null; then
  mkdir -p "${HOME}/.Trash"
  mv "$CODEX_SKILL" "${HOME}/.Trash/ronaldinho-pet-skill-$(date +%Y%m%d-%H%M%S)"
fi
if [ -d "$CODEX_CREATOR_SKILL" ] && diff -qr "$ROOT/codex-skill/create-editable-pet" "$CODEX_CREATOR_SKILL" >/dev/null; then
  mkdir -p "${HOME}/.Trash"
  mv "$CODEX_CREATOR_SKILL" "${HOME}/.Trash/create-editable-pet-skill-$(date +%Y%m%d-%H%M%S)"
fi
echo "Player Companions uninstalled. Restart Claude Code/Desktop to reload hooks."
