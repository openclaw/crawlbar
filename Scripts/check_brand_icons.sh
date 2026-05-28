#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_path="${1:-}"

required_icon_hashes=(
  "google.png:b4e8869eb52e2a8d9adfdb26e6643b61978b729a8a3a8b177815801da818c897"
  "x.png:83e0da2c51442bf79fcc47f53b3ffb1253c043329fabf98500d32cc1ee9faee7"
  "graincrawl.png:374540ba26515416a51812d6ac19b073e97e9b24bd7cd9538b5236a79cc333cd"
  "granola.png:1cd3f0db4fe8a0d1ebdfa977f308df5079f55861e652242cf7e0129382c2748a"
)

sha256_file() {
  local file_path="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file_path" | awk '{print $1}'
    return
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file_path" | awk '{print $1}'
    return
  fi
  echo "missing SHA-256 tool: expected shasum or sha256sum" >&2
  exit 1
}

check_icon_dir() {
  local icon_dir="$1"
  local label="$2"

  if [[ ! -d "$icon_dir" ]]; then
    echo "missing $label BrandIcons directory: $icon_dir" >&2
    return 1
  fi

  for icon_hash in "${required_icon_hashes[@]}"; do
    local icon="${icon_hash%%:*}"
    local expected_hash="${icon_hash#*:}"
    local icon_path="$icon_dir/$icon"
    if [[ ! -s "$icon_path" ]]; then
      echo "missing or empty $label BrandIcons/$icon" >&2
      return 1
    fi
    local actual_hash
    actual_hash="$(sha256_file "$icon_path")"
    if [[ "$actual_hash" != "$expected_hash" ]]; then
      echo "unexpected $label BrandIcons/$icon SHA-256: $actual_hash" >&2
      echo "expected: $expected_hash" >&2
      return 1
    fi
  done
}

check_icon_dir "$root_dir/Sources/CrawlBar/Resources/BrandIcons" "source" || exit 1

if [[ -n "$app_path" ]]; then
  if [[ ! -d "$app_path" ]]; then
    echo "missing app bundle: $app_path" >&2
    exit 1
  fi

  packaged_icon_dirs=()
  while IFS= read -r icon_path; do
    packaged_icon_dirs+=("$(dirname "$icon_path")")
  done < <(find "$app_path" -type f -name "google.png" | sort)
  if [[ "${#packaged_icon_dirs[@]}" -eq 0 ]]; then
    echo "missing packaged google.png under $app_path" >&2
    exit 1
  fi

  for icon_dir in "${packaged_icon_dirs[@]}"; do
    if check_icon_dir "$icon_dir" "packaged"; then
      echo "brand icons ok: source and packaged app"
      exit 0
    fi
  done

  echo "packaged app is missing one or more required brand icons" >&2
  printf 'searched directories:\n' >&2
  printf '  %s\n' "${packaged_icon_dirs[@]}" >&2
  exit 1
fi

echo "brand icons ok: source"
