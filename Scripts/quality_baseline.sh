#!/usr/bin/env bash
set -euo pipefail

# Print review metrics for CrawlBar's current shape.
#
# This is intentionally a measurement script, not a pass/fail test. Use it to
# compare a branch against itself or against main, then apply engineering
# judgment from docs/quality-rubric.md. A smaller number is only useful when it
# also removes concepts, API burden, settings clutter, or change amplification.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "== CrawlBar Quality Baseline =="
date "+generated_at=%Y-%m-%dT%H:%M:%S%z"
echo "git_status=$(git status --short | wc -l | tr -d ' ') dirty entries"
find Sources -name '*.swift' -print0 \
  | xargs -0 wc -l \
  | awk '$2 != "total" { files += 1; loc += $1 } END { print "swift_files=" files; print "swift_loc=" loc }'
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
swift package describe --type json \
  | ruby -rjson -e 'data = JSON.parse(STDIN.read); puts "products=" + data.fetch("products").map { |p| p["name"] + ":" + p.fetch("type").keys.join("+") }.join(",")'
(rg -n '^public ' Sources/CrawlBarCore || true) | wc -l | awk '{ print "public_declarations=" $1 }'
(rg -n '^package ' Sources/CrawlBarCore || true) | wc -l | awk '{ print "package_declarations=" $1 }'
echo "-- public --"
rg -n '^public ' Sources/CrawlBarCore || true
echo "-- package --"
rg -n '^package ' Sources/CrawlBarCore | sed -n '1,140p' || true
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
echo

echo "== Settings Surface Count =="
rg -n 'CrawlBarPanel|CrawlBarSwitchRow|CrawlBarControlRow|Button\s*\{|TextField|Picker' Sources/CrawlBar/Settings \
  | awk '
    /CrawlBarPanel/ { panels++ }
    /CrawlBarSwitchRow/ { switches++ }
    /CrawlBarControlRow/ { rows++ }
    /Button[[:space:]]*\{/ { buttons++ }
    /TextField/ { fields++ }
    /Picker/ { pickers++ }
    END {
      print "panels=" panels + 0
      print "switches=" switches + 0
      print "control_rows=" rows + 0
      print "buttons=" buttons + 0
      print "text_fields=" fields + 0
      print "pickers=" pickers + 0
    }'
echo

echo "== Low-Reference Type Candidates =="
ruby -e '
  require "shellwords"
  Dir["Sources/**/*.swift"].sort.each do |path|
    File.readlines(path).each do |line|
      match = line.match(/^\s*(?:public\s+|package\s+|private\s+|final\s+|internal\s+)?(?:struct|class|enum|protocol)\s+([A-Za-z_][A-Za-z0-9_]*)/)
      next unless match
      name = match[1]
      count = `rg -w #{Shellwords.escape(name)} Sources Package.swift Scripts 2>/dev/null | wc -l`.to_i
      puts "%3d %-45s %s" % [count, name, path] if count <= 3
    end
  end'
