#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
ASSET_PATH="${1:?Pass the Ronaldinho spritesheet path as the first argument.}"
BUILD_ROOT="${RONALDINHO_BUILD_ROOT:-$ROOT/build}"
APP_PATH="$BUILD_ROOT/RonaldinhoPet.app"
CONTENTS="$APP_PATH/Contents"
SDK_PATH="$(xcrun --show-sdk-path)"
ARCH="${RONALDINHO_ARCH:-$(uname -m)}"
DEPLOYMENT_TARGET="${RONALDINHO_DEPLOYMENT_TARGET:-$(xcrun --show-sdk-version)}"
TARGET="${ARCH}-apple-macosx${DEPLOYMENT_TARGET}"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-${TMPDIR:-/tmp}/ronaldinho-pet-module-cache}"

rm -rf "$APP_PATH"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
swiftc -sdk "$SDK_PATH" -target "$TARGET" -module-cache-path "$CLANG_MODULE_CACHE_PATH" "$ROOT/StateModel.swift" "$ROOT/main.swift" -o "$CONTENTS/MacOS/RonaldinhoPet" -framework Cocoa
swiftc -sdk "$SDK_PATH" -target "$TARGET" -module-cache-path "$CLANG_MODULE_CACHE_PATH" "$ROOT/StateModel.swift" "$ROOT/state-tool.swift" -o "$CONTENTS/Resources/RonaldinhoPetState"
cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"
cp "$ASSET_PATH" "$CONTENTS/Resources/spritesheet.webp"
chmod +x "$CONTENTS/MacOS/RonaldinhoPet"
chmod +x "$CONTENTS/Resources/RonaldinhoPetState"
echo "$APP_PATH"
