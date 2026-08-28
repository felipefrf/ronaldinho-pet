#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SOURCE="$ROOT/RonaldinhoPet"
PREBUILT_ROOT="${RONALDINHO_PREBUILT_ROOT:-$ROOT/prebuilt}"
TARGET_ROOT="${HOME}/Library/Application Support/RonaldinhoPet"
TARGET_APP="$TARGET_ROOT/RonaldinhoPet.app"
CLAUDE_SETTINGS="${HOME}/.claude/settings.json"
CLAUDE_COMMAND="${HOME}/.claude/commands/pet.md"
CODEX_HOOKS="${HOME}/.codex/hooks.json"
CODEX_PET="${HOME}/.codex/pets/ronaldinho-gaucho"
CODEX_SKILL="${CODEX_HOME:-${HOME}/.codex}/skills/ronaldinho-pet"
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
    if [ -e "$STAGE/previous-codex-skill" ]; then
      rm -rf "$CODEX_SKILL"
      ditto "$STAGE/previous-codex-skill" "$CODEX_SKILL"
    elif [ -e "$CODEX_SKILL" ]; then
      rm -rf "$CODEX_SKILL"
    fi
  fi
  rm -rf "$STAGE"
  exit $exit_code
}
trap rollback EXIT INT TERM

if [ "$(uname -s)" != Darwin ]; then
  echo "Player Companions supports macOS only." >&2
  exit 1
fi
if [ ! -f "$SOURCE/spritesheet.webp" ]; then
  echo "Missing spritesheet.webp." >&2
  exit 1
fi
if [ "${RONALDINHO_SKIP_HOST_CHECK:-false}" != true ] \
  && ! command -v claude >/dev/null 2>&1 && [ ! -d /Applications/Claude.app ] \
  && ! command -v codex >/dev/null 2>&1 && [ ! -d /Applications/ChatGPT.app ] && [ ! -d /Applications/Codex.app ]; then
  echo "Install Claude or Codex before enabling Player Companions." >&2
  exit 1
fi

if [ -x "$PREBUILT_ROOT/RonaldinhoPet.app/Contents/MacOS/RonaldinhoPet" ] \
  && [ -x "$PREBUILT_ROOT/RonaldinhoPet.app/Contents/Resources/RonaldinhoConfigureHooks" ]; then
  BUILD_APP="$PREBUILT_ROOT/RonaldinhoPet.app"
else
  if ! command -v swiftc >/dev/null 2>&1 || ! command -v xcrun >/dev/null 2>&1; then
    echo "Xcode Command Line Tools are required for a source install. Use the prebuilt release instead." >&2
    exit 1
  fi
  export RONALDINHO_BUILD_ROOT="$STAGE/build"
  export CLANG_MODULE_CACHE_PATH="$STAGE/module-cache"
  zsh "$SOURCE/build-app.sh" "$SOURCE/spritesheet.webp" >/dev/null
  BUILD_APP="$STAGE/build/RonaldinhoPet.app"
fi

if [ -e "$TARGET_ROOT" ]; then ditto "$TARGET_ROOT" "$STAGE/previous-install"; fi
if [ -e "$CLAUDE_SETTINGS" ]; then cp -p "$CLAUDE_SETTINGS" "$STAGE/settings.json"; fi
if [ -e "$CLAUDE_COMMAND" ]; then cp -p "$CLAUDE_COMMAND" "$STAGE/pet.md"; fi
if [ -e "$CODEX_HOOKS" ]; then cp -p "$CODEX_HOOKS" "$STAGE/hooks.json"; fi
if [ -e "$CODEX_PET" ]; then ditto "$CODEX_PET" "$STAGE/previous-codex-pet"; fi
if [ -e "$CODEX_SKILL" ]; then ditto "$CODEX_SKILL" "$STAGE/previous-codex-skill"; fi

pkill -f "$TARGET_APP/Contents/MacOS/RonaldinhoPet" 2>/dev/null || true
mkdir -p "$TARGET_ROOT"
rm -rf "$TARGET_APP"
ditto "$BUILD_APP" "$TARGET_APP"
cp "$SOURCE/show-pet.sh" "$TARGET_ROOT/show-pet.sh"
chmod +x "$TARGET_ROOT/show-pet.sh"
/usr/bin/xattr -dr com.apple.quarantine "$TARGET_ROOT" 2>/dev/null || true
CONFIGURATOR="$TARGET_APP/Contents/Resources/RonaldinhoConfigureHooks"
"$CONFIGURATOR" "$TARGET_ROOT" claude install
"$CONFIGURATOR" "$TARGET_ROOT" codex install

test -x "$TARGET_APP/Contents/MacOS/RonaldinhoPet"
test -x "$TARGET_APP/Contents/Resources/RonaldinhoPetState"
test -x "$TARGET_APP/Contents/Resources/RonaldinhoConfigureHooks"
COMMITTED=true
if [ "${RONALDINHO_SKIP_LAUNCH:-false}" != true ]; then
  open -a "$TARGET_APP" || echo "Installed, but macOS did not launch the pet. Open $TARGET_APP manually." >&2
fi

echo "Player Companions installed. If Codex asks, trust only the RonaldinhoPetState hook commands."
echo "Then restart Claude and Codex so they reload the hooks."
echo "In Codex App, open Settings → Pets → Refresh to select the native pet."
echo "Run \$ronaldinho-pet in Codex App or CLI to show the floating companion."
