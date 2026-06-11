#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/CrawlBar.app"
APP_EXEC="$APP_DIR/Contents/MacOS/CrawlBar"
DEEPLINK="crawlbar://settings"

cd "$ROOT_DIR"

find_crawlbar_pid() {
  local pid
  while IFS= read -r pid; do
    local command
    command="$(ps -p "$pid" -o command= 2>/dev/null || true)"
    if [[ "$command" == "$APP_EXEC"* ]]; then
      printf '%s\n' "$pid"
    fi
  done < <(pgrep -x CrawlBar 2>/dev/null || true)
}

wait_for_crawlbar_pid() {
  local deadline=$((SECONDS + 10))
  while ((SECONDS < deadline)); do
    local pid
    pid="$(find_crawlbar_pid | head -n 1 || true)"
    if [[ -n "$pid" ]]; then
      printf '%s\n' "$pid"
      return 0
    fi
    sleep 0.2
  done
  return 1
}

terminate_existing_crawlbar() {
  local pids
  pids="$(find_crawlbar_pid || true)"
  [[ -z "$pids" ]] && return 0

  while IFS= read -r pid; do
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
  done <<< "$pids"

  local deadline=$((SECONDS + 5))
  while ((SECONDS < deadline)); do
    [[ -z "$(find_crawlbar_pid || true)" ]] && return 0
    sleep 0.2
  done

  echo "existing CrawlBar process did not exit cleanly" >&2
  return 1
}

echo "== Package CrawlBar =="
echo "proof: builds the release app bundle and helper that a user actually runs"
Scripts/package_app.sh

echo
echo "== Check URL scheme =="
echo "proof: generated Info.plist registers crawlbar:// with LaunchServices"
/usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes:0:CFBundleURLSchemes:0" "$APP_DIR/Contents/Info.plist"

echo
echo "== Relaunch packaged app =="
echo "proof: stops only this worktree's packaged app, then launches the fresh bundle"
terminate_existing_crawlbar
/usr/bin/open -n -g "$APP_DIR"
pid="$(wait_for_crawlbar_pid)"
echo "pid=$pid"

echo
echo "== Open settings deep link =="
echo "proof: drives the public app URL surface instead of a private test hook"
/usr/bin/open -a "$APP_DIR" "$DEEPLINK"

echo
echo "== Verify settings window =="
echo "proof: uses Accessibility to confirm the Settings window loaded in this app process"
Scripts/verify_settings_window.swift --executable "$APP_EXEC" --title "CrawlBar Settings" --timeout 10 --close
