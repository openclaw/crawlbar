#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"

# shellcheck source=version.env
source "$ROOT_DIR/version.env"

architecture=universal
if [ "$#" -ne 0 ]; then
  if [ "$#" -ne 2 ] || [ "$1" != "--arch" ]; then
    echo "usage: $0 [--arch arm64|x86_64|universal]" >&2
    exit 2
  fi
  architecture="$2"
  case "$architecture" in
    arm64 | x86_64 | universal) ;;
    *) echo "unsupported architecture: $architecture" >&2; exit 2 ;;
  esac
fi

tag="v$CRAWLBAR_VERSION"
if [ "$(git -C "$ROOT_DIR" describe --tags --exact-match HEAD 2>/dev/null || true)" != "$tag" ]; then
  echo "release must run from exact tag $tag" >&2
  exit 1
fi
if [ -n "$(git -C "$ROOT_DIR" status --porcelain)" ]; then
  echo "release requires a clean checkout" >&2
  exit 1
fi

if [ -z "${NOTARYTOOL_KEYCHAIN_PROFILE:-}" ]; then
  echo "NOTARYTOOL_KEYCHAIN_PROFILE is required at runtime" >&2
  exit 1
fi

export CRAWLBAR_OFFICIAL_RELEASE=1
"$ROOT_DIR/Scripts/package_app.sh" --arch "$architecture" >/dev/null

app="$DIST_DIR/CrawlBar.app"
archive="$DIST_DIR/CrawlBar-v$CRAWLBAR_VERSION-macos.zip"
if [ "$architecture" != "universal" ]; then
  archive="$DIST_DIR/CrawlBar-v$CRAWLBAR_VERSION-macos-$architecture.zip"
fi
checksum="$archive.sha256"

create_archive() {
  rm -f "$archive"
  (
    cd "$DIST_DIR"
    COPYFILE_DISABLE=1 /usr/bin/zip -q -r -X "$(basename "$archive")" "$(basename "$app")"
  )
}

rm -f "$checksum"
create_archive
xcrun notarytool submit "$archive" --keychain-profile "$NOTARYTOOL_KEYCHAIN_PROFILE" --wait
xcrun stapler staple "$app"
xcrun stapler validate "$app"

create_archive
"$ROOT_DIR/Scripts/verify_release.sh" --require-notarized --arch "$architecture" "$archive"

(cd "$DIST_DIR" && shasum -a 256 "$(basename "$archive")" > "$(basename "$checksum")")
echo "$archive"
echo "$checksum"
