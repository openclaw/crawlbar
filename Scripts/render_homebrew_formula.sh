#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 2 && ( $# -ne 3 || "$2" != --artifacts ) ]]; then
  echo "Usage: Scripts/render_homebrew_formula.sh <version> <sha256> | <version> --artifacts <directory>" >&2
  exit 2
fi

version="$1"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Version must use x.y.z form." >&2
  exit 2
fi
artifact_sha256() {
  local suffix="-$1"
  [[ "$1" != universal ]] || suffix=""
  local archive="CrawlBar-v$version-macos$suffix.zip"
  local checksum sha256 actual
  if [[ ! -f "$2/$archive" || ! -f "$2/$archive.sha256" ]]; then
    echo "Missing archive/checksum pair: $archive" >&2
    return 1
  fi
  checksum="$(cat "$2/$archive.sha256")"
  sha256="${checksum%% *}"
  if [[ ! "$sha256" =~ ^[0-9a-f]{64}$ || "$checksum" != "$sha256  $archive" ]]; then
    echo "Invalid checksum record: $archive.sha256" >&2
    return 1
  fi
  actual="$(shasum -a 256 "$2/$archive" | awk '{print $1}')"
  if [[ "$actual" != "$sha256" ]]; then
    echo "Checksum mismatch: $archive" >&2
    return 1
  fi
  printf '%s' "$sha256"
}

architectures='%w[arm64 x86_64]'
arm_sha256=''
if [[ $# -eq 3 ]]; then
  sha256="$(artifact_sha256 universal "$3")"
  # Legacy releases have only universal. Any thin file requires the complete set.
  if [[ -e "$3/CrawlBar-v$version-macos-arm64.zip" || -e "$3/CrawlBar-v$version-macos-arm64.zip.sha256" ||
        -e "$3/CrawlBar-v$version-macos-x86_64.zip" || -e "$3/CrawlBar-v$version-macos-x86_64.zip.sha256" ]]; then
    arm_sha256="$(artifact_sha256 arm64 "$3")"
    intel_sha256="$(artifact_sha256 x86_64 "$3")"
    architectures='[Hardware::CPU.arm? ? "arm64" : "x86_64"]'
  fi
else
  sha256="$2"
  if [[ ! "$sha256" =~ ^[0-9a-f]{64}$ ]]; then
    echo "SHA-256 must be 64 lowercase hexadecimal characters." >&2
    exit 2
  fi
fi

if [[ -n "${arm_sha256:-}" ]]; then
  printf -v downloads '  url on_arch_conditional(\n    arm: "https://github.com/openclaw/crawlbar/releases/download/v@VERSION@/CrawlBar-v@VERSION@-macos-arm64.zip",\n    intel: "https://github.com/openclaw/crawlbar/releases/download/v@VERSION@/CrawlBar-v@VERSION@-macos-x86_64.zip",\n  )\n  sha256 on_arch_conditional(\n    arm: "%s",\n    intel: "%s",\n  )' "$arm_sha256" "$intel_sha256"
else
  printf -v downloads '  url "https://github.com/openclaw/crawlbar/releases/download/v@VERSION@/CrawlBar-v@VERSION@-macos.zip"\n  sha256 "%s"' "$sha256"
fi

formula="$(cat "$repo_root/packaging/homebrew/crawlbar.rb.template")"
formula="${formula//@DOWNLOADS@/$downloads}"
formula="${formula//@VERSION@/$version}"
formula="${formula//@ARCHITECTURES@/$architectures}"
printf '%s\n' "$formula"
