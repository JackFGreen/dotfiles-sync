#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/home/.config/age" "$TMP_DIR/repo/home"
age-keygen -o "$TMP_DIR/home/.config/age/keys.txt" 2>/dev/null
age-keygen -y "$TMP_DIR/home/.config/age/keys.txt" > "$TMP_DIR/recipients"
printf 'test private configuration\n' > "$TMP_DIR/expected"
age -R "$TMP_DIR/recipients" -o "$TMP_DIR/repo/home/.sample.age" "$TMP_DIR/expected"
printf 'ENCRYPTED_FILES=(".sample")\n' > "$TMP_DIR/repo/dotfiles-sync.conf"

check_decrypt() {
  local label="$1"
  shift
  if ! printf 'y\n' | "$@" "$ROOT/bin/dotfiles-sync" to-local "$TMP_DIR/repo" > "$TMP_DIR/output" 2>&1; then
    cat "$TMP_DIR/output" >&2
    printf 'FAIL: %s\n' "$label" >&2
    return 1
  fi
  cmp "$TMP_DIR/expected" "$TMP_DIR/home/.sample"
  printf 'PASS: %s\n' "$label"
}

check_decrypt 'decrypt with default identity' env -u AGE_KEYS_FILE HOME="$TMP_DIR/home"

# Require the override by moving the identity away from its default location.
mv "$TMP_DIR/home/.config/age/keys.txt" "$TMP_DIR/custom identity.txt"
rm "$TMP_DIR/home/.sample"
check_decrypt 'decrypt with custom identity' env HOME="$TMP_DIR/home" AGE_KEYS_FILE="$TMP_DIR/custom identity.txt"
