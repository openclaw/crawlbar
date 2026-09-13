#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX="${PREFIX:-$HOME/.local/bin}"

cd "$ROOT_DIR"
swift build -c release --product crawlbarctl
bin_dir="$(swift build -c release --show-bin-path)"
mkdir -p "$PREFIX"
install -m 0755 "$bin_dir/crawlbarctl" "$PREFIX/crawlbar"
echo "$PREFIX/crawlbar"
