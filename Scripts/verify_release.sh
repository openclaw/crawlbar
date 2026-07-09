#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_IDENTITY="Developer ID Application: OpenClaw Foundation (FWJYW4S8P8)"
EXPECTED_TEAM="FWJYW4S8P8"
EXPECTED_BUNDLE_ID="com.vincentkoc.CrawlBar"
require_notarized=0

if [ "${1:-}" = "--require-notarized" ]; then
  require_notarized=1
  shift
fi

artifact="${1:-}"
if [ -z "$artifact" ]; then
  echo "usage: $0 [--require-notarized] <CrawlBar.app|release.zip>" >&2
  exit 2
fi

work_dir=""
app_path="$artifact"
if [ "${artifact##*.}" = "zip" ]; then
  archive_entries="$(zipinfo -1 "$artifact")"
  if ! grep -Fqx 'CrawlBar.app/' <<<"$archive_entries"; then
    echo "release archive is missing the CrawlBar.app root" >&2
    exit 1
  fi
  while IFS= read -r entry; do
    case "$entry" in
      CrawlBar.app/ | CrawlBar.app/*) ;;
      *)
        echo "unexpected release archive member: $entry" >&2
        exit 1
        ;;
    esac
    entry_path="${entry%/}"
    case "/$entry_path/" in
      */../* | */./* | *//* | *\\*)
        echo "unsafe release archive member: $entry" >&2
        exit 1
        ;;
    esac
  done <<<"$archive_entries"
  duplicate_entry="$(LC_ALL=C sort <<<"$archive_entries" | uniq -d | head -n 1)"
  if [ -n "$duplicate_entry" ]; then
    echo "duplicate release archive member: $duplicate_entry" >&2
    exit 1
  fi

  work_dir="$(mktemp -d "${TMPDIR:-/tmp}/crawlbar-verify.XXXXXX")"
  trap 'rm -rf "$work_dir"' EXIT
  ditto -x -k "$artifact" "$work_dir"
  app_path="$work_dir/CrawlBar.app"
  unexpected_path="$(find "$work_dir" -mindepth 1 -maxdepth 1 ! -name 'CrawlBar.app' -print -quit)"
  unsafe_path="$(find "$app_path" ! -type d ! -type f -print -quit 2>/dev/null || true)"
  if [ -n "$unexpected_path" ]; then
    echo "unexpected extracted release path: $unexpected_path" >&2
    exit 1
  fi
  if [ -n "$unsafe_path" ]; then
    echo "release archive contains an unsafe link or special file: $unsafe_path" >&2
    exit 1
  fi
fi

if [ ! -d "$app_path" ]; then
  echo "missing CrawlBar.app in artifact: $artifact" >&2
  exit 1
fi

# shellcheck source=version.env
source "$ROOT_DIR/version.env"
expected_version="${CRAWLBAR_EXPECTED_VERSION:-$CRAWLBAR_VERSION}"

plist="$app_path/Contents/Info.plist"
helper="$app_path/Contents/Helpers/crawlbar"
if [ ! -f "$plist" ] || [ ! -f "$app_path/Contents/MacOS/CrawlBar" ] || [ ! -f "$helper" ]; then
  echo "release archive does not contain the exact CrawlBar app layout" >&2
  exit 1
fi
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
if [ "$bundle_id" != "$EXPECTED_BUNDLE_ID" ]; then
  echo "unexpected bundle identifier: $bundle_id" >&2
  exit 1
fi
if [ "$version" != "$expected_version" ]; then
  echo "unexpected bundle version: $version" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$app_path"
for signed_path in "$app_path" "$helper"; do
  signature="$(codesign -d --verbose=4 "$signed_path" 2>&1)"
  grep -Fqx "Authority=$EXPECTED_IDENTITY" <<<"$signature"
  grep -Fqx "TeamIdentifier=$EXPECTED_TEAM" <<<"$signature"
  grep -Eq '^CodeDirectory .* flags=.*\(runtime\)' <<<"$signature"
done

app_signature="$(codesign -d --verbose=4 "$app_path" 2>&1)"
grep -Fqx "Identifier=$EXPECTED_BUNDLE_ID" <<<"$app_signature"

for executable in "$app_path/Contents/MacOS/CrawlBar" "$helper"; do
  architectures="$(lipo -archs "$executable")"
  grep -qw arm64 <<<"$architectures"
  grep -qw x86_64 <<<"$architectures"
done

if [ "$require_notarized" = "1" ]; then
  spctl --assess --type execute --verbose=4 "$app_path"
  xcrun stapler validate "$app_path"
  syspolicy_check distribution "$app_path"
fi

echo "verified CrawlBar $version: $EXPECTED_BUNDLE_ID, $EXPECTED_TEAM, universal, hardened runtime"
