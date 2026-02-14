#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
ALLOWLIST_FILE="$ROOT_DIR/scripts/lint/dynamic_allowlist.txt"

if [ ! -f "$ALLOWLIST_FILE" ]; then
  echo "[guard:dynamic] ERROR: allowlist not found at $ALLOWLIST_FILE" >&2
  exit 1
fi

allowlist_files_tmp="$(mktemp)"
allowlist_lines_tmp="$(mktemp)"
hits_tmp="$(mktemp)"
trap 'rm -f "$allowlist_files_tmp" "$allowlist_lines_tmp" "$hits_tmp"' EXIT

while IFS= read -r raw || [ -n "$raw" ]; do
  line="${raw%%#*}"
  line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [ -z "$line" ] && continue
  if printf '%s' "$line" | grep -Eq '^.+:[0-9]+$'; then
    printf '%s\n' "$line" >> "$allowlist_lines_tmp"
  else
    printf '%s\n' "$line" >> "$allowlist_files_tmp"
  fi
done < "$ALLOWLIST_FILE"

echo "[guard:dynamic] Scanning .hx files for Dynamic usage..."
MATCHES="$(
  rg -n --no-heading --color never '\bDynamic\b' \
    --glob '*.hx' \
    --glob '!vendor/**' \
    --glob '!**/out*/**' \
    --glob '!**/intended/**' \
    --glob '!**/native/**' \
    "$ROOT_DIR" || true
)"

if [ -z "$MATCHES" ]; then
  echo "[guard:dynamic] OK (no Dynamic usage found)"
  exit 0
fi

while IFS= read -r hit || [ -n "$hit" ]; do
  [ -z "$hit" ] && continue
  file="${hit%%:*}"
  rest="${hit#*:}"
  line="${rest%%:*}"
  if ! printf '%s' "$line" | grep -Eq '^[0-9]+$'; then
    continue
  fi
  rel="${file#$ROOT_DIR/}"
  printf '%s:%s\n' "$rel" "$line" >> "$hits_tmp"
done <<< "$MATCHES"

sort -u "$hits_tmp" -o "$hits_tmp"

violations=0
while IFS= read -r hit || [ -n "$hit" ]; do
  [ -z "$hit" ] && continue
  rel="${hit%:*}"
  if ! grep -Fxq "$rel" "$allowlist_files_tmp" && ! grep -Fxq "$hit" "$allowlist_lines_tmp"; then
    if [ $violations -eq 0 ]; then
      echo "[guard:dynamic] ERROR: Non-allowlisted Dynamic usage detected:" >&2
    fi
    echo "[guard:dynamic] $hit" >&2
    violations=$((violations + 1))
  fi
done < "$hits_tmp"

if [ $violations -ne 0 ]; then
  echo "[guard:dynamic] Update code to remove Dynamic or explicitly justify and add the exact line (path:line) to scripts/lint/dynamic_allowlist.txt." >&2
  exit 1
fi

echo "[guard:dynamic] OK"
