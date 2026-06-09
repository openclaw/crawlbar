#!/usr/bin/env bash
set -euo pipefail

# Print the small set of review metrics used by docs/quality-rubric.md.
# This script deliberately does not pass or fail a build. It gives reviewers
# handles for complexity: file size, type clustering, public API surface,
# platform/effect ownership, settings clutter, and possible one-off types.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

section() {
  local title="$1"
  local why="$2"

  echo
  echo "== ${title} =="
  echo "why=${why}"
}

echo "== CrawlBar Quality Baseline =="
echo "why=stamp the exact repo state so before/after comparisons are evidence-based"
date "+generated_at=%Y-%m-%dT%H:%M:%S%z"
echo "git_status=$(git status --short | wc -l | tr -d ' ') dirty entries"
find Sources -name '*.swift' -print0 \
  | xargs -0 wc -l \
  | awk '$2 != "total" { files += 1; loc += $1 } END { print "swift_files=" files; print "swift_loc=" loc }'

section "Largest Swift Files" \
  "large files are expensive to scan; this points reviewers to the biggest reading costs"
find Sources -name '*.swift' -print0 \
  | xargs -0 wc -l \
  | awk '$2 != "total" { print }' \
  | sort -nr \
  | head -30

section "Files Over 400 Lines" \
  "the repo standard says new files should stay under roughly 400 LOC"
find Sources -name '*.swift' -print0 \
  | xargs -0 wc -l \
  | awk '$2 != "total" && $1 > 400 { print }' \
  | sort -nr

section "Top-Level Type Counts" \
  "many types in one file usually means a grab bag or hidden design system"
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

section "CrawlBarCore Interface Surface" \
  "CrawlBarCore is shipped as a library; these counts show review surface, not complete symbol compatibility"
products="$(
  swift package describe \
    | awk '
      /^Products:/ { in_products = 1; next }
      /^Targets:/ { in_products = 0 }
      in_products && /^    Name:/ { name = $2; next }
      in_products && /^        Library:/ { print name ":library"; next }
      in_products && /^        Executable:/ { print name ":executable"; next }
    ' \
    | paste -sd, -
)"
echo "products=${products}"
(rg -n '^public ' Sources/CrawlBarCore || true) | wc -l | awk '{ print "raw_public_lines=" $1 }'
(rg -n '^package ' Sources/CrawlBarCore || true) | wc -l | awk '{ print "raw_package_lines=" $1 }'
echo "note=public extension members are public API but are not counted as raw public lines; use Swift symbol graphs for compatibility checks"
echo "-- public --"
rg -n '^public ' Sources/CrawlBarCore || true
echo "-- package --"
rg -n '^package ' Sources/CrawlBarCore | sed -n '1,140p' || true

section "Forbidden Core UI Imports" \
  "Core should stay UI-free; AppKit/SwiftUI belongs in the app target"
rg -n 'import (AppKit|SwiftUI)' Sources/CrawlBarCore || true

section "Production Effect/Platform References" \
  "process, filesystem, AppKit, UserDefaults, and task ownership should sit in intentional boundaries"
rg -n 'Process\(|FileManager\.|NSWorkspace|NSApp|NSWindow|NSMenu|NSStatus|UserDefaults|Task\s*\{' Sources/CrawlBar Sources/CrawlBarCore Sources/CrawlBarCLI Sources/CrawlBarSelfTest \
  | rg -v '^Sources/CrawlBarSelfTest/' \
  | sed -n '1,200p'

section "SelfTest Effect/Platform References" \
  "test harnesses are allowed more effects, but the count shows how broad the proof surface is"
rg -n 'Process\(|FileManager\.|NSWorkspace|NSApp|NSWindow|NSMenu|NSStatus|UserDefaults|Task\s*\{' Sources/CrawlBarSelfTest \
  | wc -l \
  | awk '{ print "references=" $1 }'

section "UI Candidate Types By Folder" \
  "shows where SwiftUI/AppKit concepts cluster so UI decomposition does not create one-off primitives everywhere"
rg -n '^(struct|class|enum|protocol) .*(: .*View|View\b|Window|Menu|Sidebar|Panel|Row|Header|Section|Controls|Icon|Status|Settings)' Sources/CrawlBar \
  | awk -F: '{ print $1 }' \
  | awk -F/ '{ print $1 "/" $2 "/" $3 }' \
  | sort \
  | uniq -c \
  | sort -nr

section "Settings Surface Count" \
  "counts user-facing controls; high counts mean the simple menubar app may be carrying too many knobs"
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

section "Low-Reference Type Candidates" \
  "types with 1-3 textual references are not automatically dead; they are review handles for unused code, one-off wrappers, and speculative helpers"
find Sources -name '*.swift' -print0 \
  | while IFS= read -r -d '' path; do
      awk -v path="$path" '
        {
          line = $0
          sub(/^[[:space:]]*/, "", line)
          sub(/^(public|package|private|final|internal)[[:space:]]+/, "", line)
          if (line ~ /^(struct|class|enum|protocol)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/) {
            split(line, parts, /[[:space:]]+/)
            sub(/[:<{].*/, "", parts[2])
            print path "\t" parts[2]
          }
        }
      ' "$path"
    done \
  | while IFS=$'\t' read -r path name; do
      reference_count="$(rg -w -- "$name" Sources Package.swift Scripts 2>/dev/null | wc -l | tr -d ' ')"
      if (( reference_count <= 3 )); then
        printf "%3d %-45s %s\n" "$reference_count" "$name" "$path"
      fi
    done
