#!/bin/zsh
set -euo pipefail

ACTION="${1:-install}"
[[ "$ACTION" == install || "$ACTION" == uninstall ]] || {
  echo "Usage: install-remote.sh [install|uninstall]" >&2
  exit 1
}
[[ "$(uname -s)" == Darwin ]] || {
  echo "Ronaldinho Pet currently supports macOS only." >&2
  exit 1
}

REPOSITORY="felipefrf/ronaldinho-pet"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/ronaldinho-pet-remote.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

TAG="${RONALDINHO_TAG:-}"
if [[ -z "$TAG" ]]; then
  /usr/bin/curl -fsSL \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$REPOSITORY/releases?per_page=1" \
    -o "$STAGE/releases.json"
  TAG="$(/usr/bin/plutil -extract 0.tag_name raw -o - "$STAGE/releases.json")"
fi
VERSION="${TAG#v}"
ARCHIVE="RonaldinhoPet-$VERSION-macos-universal.zip"
CHECKSUMS="RonaldinhoPet-$VERSION-macos-universal.sha256"
BASE_URL="${RONALDINHO_DOWNLOAD_BASE:-https://github.com/$REPOSITORY/releases/download/$TAG}"

echo "Downloading Ronaldinho Pet $TAG…"
/usr/bin/curl -fsSL "$BASE_URL/$ARCHIVE" -o "$STAGE/$ARCHIVE"
/usr/bin/curl -fsSL "$BASE_URL/$CHECKSUMS" -o "$STAGE/$CHECKSUMS"
EXPECTED="$(awk -v archive="$ARCHIVE" '$2 == archive { print $1; exit }' "$STAGE/$CHECKSUMS")"
ACTUAL="$(/usr/bin/shasum -a 256 "$STAGE/$ARCHIVE" | awk '{ print $1 }')"
[[ -n "$EXPECTED" && "$EXPECTED" == "$ACTUAL" ]] || {
  echo "Checksum verification failed. Nothing was installed." >&2
  exit 1
}

mkdir -p "$STAGE/package"
/usr/bin/ditto -x -k "$STAGE/$ARCHIVE" "$STAGE/package"
PACKAGE="$STAGE/package/Ronaldinho Pet"
[[ -x "$PACKAGE/$ACTION.sh" ]] || {
  echo "Release package is missing $ACTION.sh." >&2
  exit 1
}

"$PACKAGE/$ACTION.sh"
