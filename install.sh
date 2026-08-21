#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SOURCE="$ROOT/RonaldinhoPet"
TARGET_ROOT="${HOME}/Library/Application Support/RonaldinhoPet"
TARGET_APP="$TARGET_ROOT/RonaldinhoPet.app"
CLAUDE_SETTINGS="${HOME}/.claude/settings.json"
CLAUDE_COMMAND="${HOME}/.claude/commands/pet.md"
CODEX_HOOKS="${HOME}/.codex/hooks.json"
CODEX_PET="${HOME}/.codex/pets/ronaldinho-gaucho"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/ronaldinho-pet-install.XXXXXX")"
COMMITTED=false

rollback() {
  local exit_code=$?
  if [ "$COMMITTED" = false ]; then
    if [ -e "$STAGE/previous-install" ]; then
      rm -rf "$TARGET_ROOT"
      ditto "$STAGE/previous-install" "$TARGET_ROOT"
    elif [ -e "$TARGET_ROOT" ]; then
      rm -rf "$TARGET_ROOT"
    fi
    if [ -e "$STAGE/settings.json" ]; then
      cp -p "$STAGE/settings.json" "$CLAUDE_SETTINGS"
    elif [ -e "$CLAUDE_SETTINGS" ]; then
      rm -f "$CLAUDE_SETTINGS"
    fi
    if [ -e "$STAGE/pet.md" ]; then
      mkdir -p "${CLAUDE_COMMAND:h}"
      cp -p "$STAGE/pet.md" "$CLAUDE_COMMAND"
    elif [ -e "$CLAUDE_COMMAND" ]; then
      rm -f "$CLAUDE_COMMAND"
    fi
    if [ -e "$STAGE/hooks.json" ]; then
      cp -p "$STAGE/hooks.json" "$CODEX_HOOKS"
    elif [ -e "$CODEX_HOOKS" ]; then
      rm -f "$CODEX_HOOKS"
    fi
    if [ -e "$STAGE/previous-codex-pet" ]; then
      rm -rf "$CODEX_PET"
      ditto "$STAGE/previous-codex-pet" "$CODEX_PET"
    elif [ -e "$CODEX_PET" ]; then
      rm -rf "$CODEX_PET"
    fi
  fi
  rm -rf "$STAGE"
  exit $exit_code
}
trap rollback EXIT INT TERM

if [ "$(uname -s)" != Darwin ]; then
  echo "Ronaldinho Pet supports macOS only." >&2
  exit 1
fi
if ! command -v swiftc >/dev/null 2>&1 || ! command -v xcrun >/dev/null 2>&1; then
  echo "Xcode Command Line Tools are required. Run: xcode-select --install" >&2
  exit 1
fi
if [ ! -f "$SOURCE/spritesheet.webp" ]; then
  echo "Missing spritesheet.webp." >&2
  exit 1
fi
if ! command -v claude >/dev/null 2>&1 && [ ! -d /Applications/Claude.app ]; then
  echo "Install Claude Code or Claude Desktop before enabling Claude hooks." >&2
  exit 1
fi

export RONALDINHO_BUILD_ROOT="$STAGE/build"
export CLANG_MODULE_CACHE_PATH="$STAGE/module-cache"
zsh "$SOURCE/build-app.sh" "$SOURCE/spritesheet.webp" >/dev/null
SDK_PATH="$(xcrun --show-sdk-path)"
SDK_VERSION="$(xcrun --show-sdk-version)"
swiftc -sdk "$SDK_PATH" -target "$(uname -m)-apple-macosx${SDK_VERSION}" \
  "$SOURCE/configure-hooks.swift" -o "$STAGE/configure-hooks"

if [ -e "$TARGET_ROOT" ]; then ditto "$TARGET_ROOT" "$STAGE/previous-install"; fi
if [ -e "$CLAUDE_SETTINGS" ]; then cp -p "$CLAUDE_SETTINGS" "$STAGE/settings.json"; fi
if [ -e "$CLAUDE_COMMAND" ]; then cp -p "$CLAUDE_COMMAND" "$STAGE/pet.md"; fi
if [ -e "$CODEX_HOOKS" ]; then cp -p "$CODEX_HOOKS" "$STAGE/hooks.json"; fi
if [ -e "$CODEX_PET" ]; then ditto "$CODEX_PET" "$STAGE/previous-codex-pet"; fi

pkill -f "$TARGET_APP/Contents/MacOS/RonaldinhoPet" 2>/dev/null || true
mkdir -p "$TARGET_ROOT"
rm -rf "$TARGET_APP"
ditto "$STAGE/build/RonaldinhoPet.app" "$TARGET_APP"
cp "$SOURCE/show-pet.sh" "$TARGET_ROOT/show-pet.sh"
chmod +x "$TARGET_ROOT/show-pet.sh"
"$STAGE/configure-hooks" "$TARGET_ROOT" claude install
"$STAGE/configure-hooks" "$TARGET_ROOT" codex install
mkdir -p "$CODEX_PET"
cp "$ROOT/codex-pet/pet.json" "$ROOT/RonaldinhoPet/spritesheet.webp" "$CODEX_PET/"

test -x "$TARGET_APP/Contents/MacOS/RonaldinhoPet"
test -x "$TARGET_APP/Contents/Resources/RonaldinhoPetState"
COMMITTED=true
if [ "${RONALDINHO_SKIP_LAUNCH:-false}" != true ]; then
  open -a "$TARGET_APP" || echo "Installed, but macOS did not launch the pet. Open $TARGET_APP manually." >&2
fi

echo "Ronaldinho Pet installed. In Codex CLI, run /hooks and trust the RonaldinhoPetState commands."
echo "Then restart Claude and Codex so they reload the trusted hooks."
echo "In Codex App, open Settings → Pets → Refresh to select the native pet."
