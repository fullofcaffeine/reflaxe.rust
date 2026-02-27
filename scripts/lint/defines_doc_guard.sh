#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
src_dir="$root_dir/src/reflaxe/rust"
doc_file="$root_dir/docs/defines-reference.md"

if [[ ! -d "$src_dir" ]]; then
  echo "[guard:defines-doc] ERROR: compiler source directory not found: $src_dir" >&2
  exit 2
fi

if [[ ! -f "$doc_file" ]]; then
  echo "[guard:defines-doc] ERROR: missing docs file: $doc_file" >&2
  exit 2
fi

extract_defines_rg() {
  rg -No 'Context\.defined(?:Value)?\("([^"]+)"\)' "$src_dir" \
    | sed -E 's/.*\("([^"]+)"\).*/\1/' \
    | sort -u
}

extract_defines_grep() {
  grep -RhoE 'Context\.defined(Value)?\("([^"]+)"\)' "$src_dir" \
    | sed -E 's/.*\("([^"]+)"\).*/\1/' \
    | sort -u
}

if [[ "${REFLAXE_NO_RG:-0}" != "1" ]] && command -v rg >/dev/null 2>&1; then
  raw_defines="$(extract_defines_rg)"
else
  raw_defines="$(extract_defines_grep)"
fi

if [[ -z "$raw_defines" ]]; then
  echo "[guard:defines-doc] ERROR: no defines discovered under $src_dir" >&2
  exit 2
fi

missing=()
while IFS= read -r define; do
  [[ -n "$define" ]] || continue
  case "$define" in
    rust_*|reflaxe_rust_*)
      pattern="\`${define}([[:space:]]*=[^\\\`]+)?\`"
      if ! grep -Eq "$pattern" "$doc_file"; then
        missing+=("$define")
      fi
      ;;
    *)
      ;;
  esac
done <<< "$raw_defines"

if [[ "${#missing[@]}" -gt 0 ]]; then
  echo "[guard:defines-doc] ERROR: compiler defines missing from docs/defines-reference.md:" >&2
  for define in "${missing[@]}"; do
    echo "[guard:defines-doc] $define" >&2
  done
  exit 1
fi

echo "[guard:defines-doc] OK"
