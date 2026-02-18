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

allowlist_parse_errors=0
while IFS= read -r raw || [ -n "$raw" ]; do
  trimmed_raw="$(printf '%s' "$raw" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [ -z "$trimmed_raw" ] && continue
  if printf '%s' "$trimmed_raw" | grep -Eq '^#'; then
    continue
  fi

  line="${trimmed_raw%%#*}"
  line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [ -z "$line" ] && continue
  if printf '%s' "$line" | grep -Eq '^.+:[0-9]+$'; then
    printf '%s\n' "$line" >> "$allowlist_lines_tmp"
  else
    if ! printf '%s' "$trimmed_raw" | grep -Eq '#[[:space:]]*FILE_SCOPE_JUSTIFICATION:[[:space:]]*.+$'; then
      if [ $allowlist_parse_errors -eq 0 ]; then
        echo "[guard:dynamic] ERROR: File-scoped allowlist entries require an inline justification comment." >&2
      fi
      echo "[guard:dynamic] $line (missing '# FILE_SCOPE_JUSTIFICATION: ...')" >&2
      allowlist_parse_errors=$((allowlist_parse_errors + 1))
    fi
    printf '%s\n' "$line" >> "$allowlist_files_tmp"
  fi
done < "$ALLOWLIST_FILE"

if [ $allowlist_parse_errors -ne 0 ]; then
  exit 1
fi

echo "[guard:dynamic] Scanning Haxe source files (.hx / .cross.hx) for Dynamic usage..."

# Find candidate files quickly, then run a lightweight comment-aware scan per file so
# comment-only mentions (including block-doc text) don't churn the allowlist.
CANDIDATE_FILES="$(
  rg -l --no-heading --color never '\bDynamic\b' \
    --glob '*.hx' \
    --glob '!vendor/**' \
    --glob '!**/out*/**' \
    --glob '!**/intended/**' \
    --glob '!**/native/**' \
    "$ROOT_DIR" || true
)"

if [ -z "$CANDIDATE_FILES" ]; then
  echo "[guard:dynamic] OK (no Dynamic usage found)"
  exit 0
fi

while IFS= read -r file || [ -n "$file" ]; do
  [ -z "$file" ] && continue

  awk '
    BEGIN {
      in_block = 0;
    }
    {
      line = $0;
      code = "";
      i = 1;
      in_str = 0;
      str_ch = "";

      while (i <= length(line)) {
        c = substr(line, i, 1);
        two = substr(line, i, 2);

        if (in_block) {
          if (two == "*/") {
            in_block = 0;
            i += 2;
            continue;
          }
          i++;
          continue;
        }

        if (in_str) {
          code = code c;
          if (c == "\\") {
            if (i < length(line)) {
              code = code substr(line, i + 1, 1);
              i += 2;
              continue;
            }
          }
          if (c == str_ch) {
            in_str = 0;
            str_ch = "";
          }
          i++;
          continue;
        }

        if (two == "/*") {
          in_block = 1;
          i += 2;
          continue;
        }
        if (two == "//") {
          break;
        }
        if (c == "\"" || c == "'\''") {
          in_str = 1;
          str_ch = c;
          code = code c;
          i++;
          continue;
        }

        code = code c;
        i++;
      }

      if (code ~ /(^|[^[:alnum:]_])Dynamic([^[:alnum:]_]|$)/) {
        print FNR;
      }
    }
  ' "$file" | while IFS= read -r line || [ -n "$line" ]; do
    [ -z "$line" ] && continue
    rel="${file#$ROOT_DIR/}"
    printf '%s:%s\n' "$rel" "$line" >> "$hits_tmp"
  done
done <<< "$CANDIDATE_FILES"

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
