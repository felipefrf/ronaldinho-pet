#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
VERSION="${1:?Usage: ./package-release.sh <version>}"
DEPLOYMENT_TARGET="${RONALDINHO_DEPLOYMENT_TARGET:-13.0}"
DIST="$ROOT/dist"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/ronaldinho-pet-release.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

SDK_PATH="$(xcrun --show-sdk-path)"
for arch in arm64 x86_64; do
  RONALDINHO_ARCH="$arch" \
  RONALDINHO_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
  RONALDINHO_BUILD_ROOT="$STAGE/build-$arch" \
  CLANG_MODULE_CACHE_PATH="$STAGE/module-cache-$arch" \
    zsh "$ROOT/RonaldinhoPet/build-app.sh" "$ROOT/RonaldinhoPet/spritesheet.webp" >/dev/null
  swiftc -sdk "$SDK_PATH" -target "$arch-apple-macosx$DEPLOYMENT_TARGET" -module-cache-path "$STAGE/module-cache-$arch" \
    "$ROOT/RonaldinhoPet/configure-hooks.swift" -o "$STAGE/configure-hooks-$arch"
done

PACKAGE="$STAGE/Ronaldinho Pet"
PREBUILT="$PACKAGE/prebuilt"
mkdir -p "$PREBUILT" "$PACKAGE/RonaldinhoPet"
ditto "$STAGE/build-arm64/RonaldinhoPet.app" "$PREBUILT/RonaldinhoPet.app"
lipo -create \
  "$STAGE/build-arm64/RonaldinhoPet.app/Contents/MacOS/RonaldinhoPet" \
  "$STAGE/build-x86_64/RonaldinhoPet.app/Contents/MacOS/RonaldinhoPet" \
  -output "$PREBUILT/RonaldinhoPet.app/Contents/MacOS/RonaldinhoPet"
lipo -create \
  "$STAGE/build-arm64/RonaldinhoPet.app/Contents/Resources/RonaldinhoPetState" \
  "$STAGE/build-x86_64/RonaldinhoPet.app/Contents/Resources/RonaldinhoPetState" \
  -output "$PREBUILT/RonaldinhoPet.app/Contents/Resources/RonaldinhoPetState"
lipo -create "$STAGE/configure-hooks-arm64" "$STAGE/configure-hooks-x86_64" \
  -output "$PREBUILT/configure-hooks"

cp "$ROOT/install.sh" "$ROOT/uninstall.sh" "$ROOT/README.md" "$ROOT/LICENSE" "$ROOT/ASSET_NOTICE.md" "$PACKAGE/"
cp "$ROOT/RonaldinhoPet/show-pet.sh" "$ROOT/RonaldinhoPet/spritesheet.webp" "$PACKAGE/RonaldinhoPet/"
ditto "$ROOT/codex-pet" "$PACKAGE/codex-pet"
ditto "$ROOT/codex-skill" "$PACKAGE/codex-skill"
cp "$ROOT/distribution/Install Ronaldinho Pet.command" "$ROOT/distribution/Uninstall Ronaldinho Pet.command" "$PACKAGE/"
chmod +x "$PACKAGE"/*.sh "$PACKAGE"/*.command "$PREBUILT/configure-hooks"
/usr/bin/xattr -cr "$PACKAGE"

codesign --force --deep --sign "${RONALDINHO_CODESIGN_IDENTITY:--}" "$PREBUILT/RonaldinhoPet.app"
codesign --force --sign "${RONALDINHO_CODESIGN_IDENTITY:--}" "$PREBUILT/configure-hooks"
for binary in "$PREBUILT/RonaldinhoPet.app/Contents/MacOS/RonaldinhoPet" "$PREBUILT/configure-hooks"; do
  archs=" $(lipo -archs "$binary") "
  echo "$(basename "$binary"): $archs"
  [[ "$archs" == *" arm64 "* && "$archs" == *" x86_64 "* ]]
done

rm -rf "$DIST"
mkdir -p "$DIST"
ARCHIVE="RonaldinhoPet-$VERSION-macos-universal"
ditto -c -k --keepParent "$PACKAGE" "$DIST/$ARCHIVE.zip"
artifacts=("$ARCHIVE.zip")
if [ "${RONALDINHO_SKIP_DMG:-false}" != true ]; then
  hdiutil create -volname "Ronaldinho Pet" -srcfolder "$PACKAGE" -ov -format UDZO "$DIST/$ARCHIVE.dmg"
  artifacts+=("$ARCHIVE.dmg")
fi
(
  cd "$DIST"
  shasum -a 256 "${artifacts[@]}" > "$ARCHIVE.sha256"
)
echo "$DIST"
