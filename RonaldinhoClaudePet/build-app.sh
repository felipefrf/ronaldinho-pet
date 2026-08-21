#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
ASSET_PATH="${1:?Pass the Ronaldinho spritesheet path as the first argument.}"
APP_PATH="$ROOT/RonaldinhoClaudePet.app"
CONTENTS="$APP_PATH/Contents"

mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
swiftc "$ROOT/main.swift" -o "$CONTENTS/MacOS/RonaldinhoClaudePet" -framework Cocoa
swiftc "$ROOT/state-tool.swift" -o "$CONTENTS/Resources/RonaldinhoPetState"
cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"
cp "$ASSET_PATH" "$CONTENTS/Resources/spritesheet.webp"
chmod +x "$CONTENTS/MacOS/RonaldinhoClaudePet"
chmod +x "$CONTENTS/Resources/RonaldinhoPetState"
echo "$APP_PATH"
