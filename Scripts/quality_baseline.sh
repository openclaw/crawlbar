#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "== CrawlBar Quality Baseline =="
date "+generated_at=%Y-%m-%dT%H:%M:%S%z"
echo "git_status=$(git status --short | wc -l | tr -d ' ') dirty entries"
echo

echo "== Largest Swift Files =="
find Sources -name '*.swift' -print0 \
  | xargs -0 wc -l \
  | awk '$2 != "total" { print }' \
  | sort -nr \
  | head -30
echo

echo "== Files Over 400 Lines =="
find Sources -name '*.swift' -print0 \
  | xargs -0 wc -l \
  | awk '$2 != "total" && $1 > 400 { print }' \
  | sort -nr
echo

echo "== Top-Level Type Counts =="
find Sources -name '*.swift' -print0 \
  | xargs -0 awk '
    FNR == 1 {
      if (file != "") print count, file
      file = FILENAME
      count = 0
    }
    /^(public |package |internal |private )?(struct|class|enum|actor|protocol) / { count++ }
    END { if (file != "") print count, file }
  ' \
  | sort -nr \
  | head -30
echo

echo "== CrawlBarCore Interface Surface =="
(rg -n '^public ' Sources/CrawlBarCore || true) | wc -l | awk '{ print "public_declarations=" $1 }'
(rg -n '^package ' Sources/CrawlBarCore || true) | wc -l | awk '{ print "package_declarations=" $1 }'
echo "-- public --"
rg -n '^public ' Sources/CrawlBarCore || true
echo "-- package --"
rg -n '^package ' Sources/CrawlBarCore | sed -n '1,140p'
echo

echo "== Forbidden Core UI Imports =="
rg -n 'import (AppKit|SwiftUI)' Sources/CrawlBarCore || true
echo

echo "== Production Effect/Platform References =="
rg -n 'Process\(|FileManager\.|NSWorkspace|NSApp|NSWindow|NSMenu|NSStatus|UserDefaults|Task\s*\{' Sources/CrawlBar Sources/CrawlBarCore Sources/CrawlBarCLI Sources/CrawlBarSelfTest \
  | rg -v '^Sources/CrawlBarSelfTest/' \
  | sed -n '1,200p'
echo

echo "== SelfTest Effect/Platform References =="
rg -n 'Process\(|FileManager\.|NSWorkspace|NSApp|NSWindow|NSMenu|NSStatus|UserDefaults|Task\s*\{' Sources/CrawlBarSelfTest \
  | wc -l \
  | awk '{ print "references=" $1 }'
echo

echo "== UI Candidate Types By Folder =="
rg -n '^(struct|class|enum|protocol) .*(: .*View|View\b|Window|Menu|Sidebar|Panel|Row|Header|Section|Controls|Icon|Status|Settings)' Sources/CrawlBar \
  | awk -F: '{ print $1 }' \
  | awk -F/ '{ print $1 "/" $2 "/" $3 }' \
  | sort \
  | uniq -c \
  | sort -nr
