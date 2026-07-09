#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/CrawlBar.app"
STAGING_APP_DIR="$DIST_DIR/.CrawlBar.app.tmp.$$"
BUILD_DIR="${TMPDIR:-/tmp}/crawlbar-package.$$"
CONTENTS_DIR="$STAGING_APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
HELPERS_DIR="$CONTENTS_DIR/Helpers"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
EXPECTED_IDENTITY="Developer ID Application: OpenClaw Foundation (FWJYW4S8P8)"

# shellcheck source=version.env
source "$ROOT_DIR/version.env"

official_release="${CRAWLBAR_OFFICIAL_RELEASE:-0}"
universal_build="${CRAWLBAR_UNIVERSAL:-$official_release}"
signing_identity="${CRAWLBAR_CODESIGN_IDENTITY:-${MAC_RELEASE_CODESIGN_IDENTITY:-}}"

if [ "$official_release" = "1" ] && [ "$signing_identity" != "$EXPECTED_IDENTITY" ]; then
  echo "official release requires signing identity: $EXPECTED_IDENTITY" >&2
  exit 1
fi

cd "$ROOT_DIR"
mkdir -p "$DIST_DIR"

if [ "$universal_build" = "1" ]; then
  for arch in arm64 x86_64; do
    swift build \
      -c release \
      --triple "${arch}-apple-macosx14.0" \
      --scratch-path "$BUILD_DIR/$arch" \
      --product CrawlBar >&2
    swift build \
      -c release \
      --triple "${arch}-apple-macosx14.0" \
      --scratch-path "$BUILD_DIR/$arch" \
      --product crawlbarctl >&2
  done
  arm_release="$BUILD_DIR/arm64/arm64-apple-macosx/release"
  intel_release="$BUILD_DIR/x86_64/x86_64-apple-macosx/release"
  resource_bundle="$arm_release/CrawlBar_CrawlBar.bundle"
else
  swift build -c release --product CrawlBar >&2
  swift build -c release --product crawlbarctl >&2
  native_release="$ROOT_DIR/.build/release"
  resource_bundle="$native_release/CrawlBar_CrawlBar.bundle"
fi

rm -rf "$STAGING_APP_DIR"
trap 'rm -rf "$STAGING_APP_DIR" "$BUILD_DIR"' EXIT
mkdir -p "$MACOS_DIR" "$HELPERS_DIR" "$RESOURCES_DIR"

if [ "$universal_build" = "1" ]; then
  lipo -create \
    "$arm_release/CrawlBar" \
    "$intel_release/CrawlBar" \
    -output "$MACOS_DIR/CrawlBar"
  lipo -create \
    "$arm_release/crawlbarctl" \
    "$intel_release/crawlbarctl" \
    -output "$HELPERS_DIR/crawlbar"
else
  cp "$native_release/CrawlBar" "$MACOS_DIR/CrawlBar"
  cp "$native_release/crawlbarctl" "$HELPERS_DIR/crawlbar"
fi

if [ -d "$resource_bundle" ]; then
  cp -R "$resource_bundle" "$RESOURCES_DIR/CrawlBar_CrawlBar.bundle"
  if ! find "$RESOURCES_DIR/CrawlBar_CrawlBar.bundle" -type f -print -quit | grep -q .; then
    echo "SwiftPM resource bundle is empty: $resource_bundle" >&2
    exit 1
  fi
else
  echo "missing SwiftPM resource bundle: $resource_bundle" >&2
  exit 1
fi
Scripts/generate_app_icon.swift "$RESOURCES_DIR/CrawlBar.icns"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>CrawlBar</string>
  <key>CFBundleIdentifier</key>
  <string>com.vincentkoc.CrawlBar</string>
  <key>CFBundleName</key>
  <string>CrawlBar</string>
  <key>CFBundleIconFile</key>
  <string>CrawlBar</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$CRAWLBAR_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$CRAWLBAR_BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

if [ "$official_release" = "1" ]; then
  codesign --force --options runtime --timestamp --sign "$signing_identity" "$HELPERS_DIR/crawlbar"
  codesign --force --options runtime --timestamp --sign "$signing_identity" "$STAGING_APP_DIR"
  "$ROOT_DIR/Scripts/verify_release.sh" "$STAGING_APP_DIR"
elif command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$STAGING_APP_DIR" >/dev/null
fi

rm -rf "$APP_DIR"
mv "$STAGING_APP_DIR" "$APP_DIR"
echo "$APP_DIR"
