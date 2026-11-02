#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Reproduce npm's global bin layout, including paths containing spaces.
mkdir -p "$TMP_DIR/prefix/bin" "$TMP_DIR/prefix/lib/node_modules/tool package" \
  "$TMP_DIR/home" "$TMP_DIR/repo/home"
cp -R "$ROOT/bin" "$ROOT/lib" "$TMP_DIR/prefix/lib/node_modules/tool package/"
ln -s '../lib/node_modules/tool package/bin/dotfiles-sync' "$TMP_DIR/prefix/bin/dotfiles-sync"
printf 'SYNC_FILES=(".sample")\n' > "$TMP_DIR/repo/dotfiles-sync.conf"
printf 'sample\n' > "$TMP_DIR/home/.sample"
cp "$TMP_DIR/home/.sample" "$TMP_DIR/repo/home/.sample"

check_diff() {
  local output
  if ! output=$(HOME="$TMP_DIR/home" "$1" diff "$TMP_DIR/repo" 2>&1); then
    printf 'FAIL: %s\n%s\n' "$1" "$output" >&2
    return 1
  fi
  if [[ "$output" != *'无差异。'* ]]; then
    printf 'FAIL: expected no differences\n%s\n' "$output" >&2
    return 1
  fi
  printf 'PASS: %s\n' "$1"
}

check_diff "$TMP_DIR/prefix/lib/node_modules/tool package/bin/dotfiles-sync"
check_diff "$TMP_DIR/prefix/bin/dotfiles-sync"
ln -s "$TMP_DIR/prefix/bin/dotfiles-sync" "$TMP_DIR/chained-link"
check_diff "$TMP_DIR/chained-link"
