#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "[guard:local-paths] WARN: no git repo at project root; skipping staged scan."
  exit 0
fi

use_rg=0
if [[ "${REFLAXE_NO_RG:-0}" != "1" ]] && command -v rg >/dev/null 2>&1; then
  use_rg=1
fi

STAGED_ADDED_LINES="$(
  git diff --cached --unified=0 --no-color -- . \
    | awk '
      /^diff --git / { file = ""; next }
      /^\+\+\+ / {
        file = $2
        if (file == "/dev/null") {
          file = ""
        } else {
          sub(/^[a-z]\//, "", file)
        }
        next
      }
      /^\+/ && $0 !~ /^\+\+\+/ && file != "" {
        print file ":" substr($0, 2)
      }
    '
)"

if [[ -z "$STAGED_ADDED_LINES" ]]; then
  exit 0
fi

ABSOLUTE_LOCAL_PATTERN="(/Users/[^[:space:]\"'<>()[\\]{}]+|/home/[^[:space:]\"'<>()[\\]{}]+|/var/folders/[^[:space:]\"'<>()[\\]{}]+|/private/var/folders/[^[:space:]\"'<>()[\\]{}]+|[A-Za-z]:\\\\Users\\\\[^[:space:]\"'<>()[\\]{}]+)"
RELATIVE_PATH_PATTERN="(^|[^[:alnum:]_])(\\./|\\.\\./)[^[:space:]\"'<>()[\\]{}]+"

if [[ "$use_rg" -eq 1 ]]; then
  ABSOLUTE_HITS="$(printf '%s\n' "$STAGED_ADDED_LINES" | rg -n -P "$ABSOLUTE_LOCAL_PATTERN" || true)"
else
  ABSOLUTE_HITS="$(printf '%s\n' "$STAGED_ADDED_LINES" | grep -En "$ABSOLUTE_LOCAL_PATTERN" || true)"
fi
if [[ -n "$ABSOLUTE_HITS" ]]; then
  echo "[guard:local-paths] ERROR: Absolute local filesystem paths detected in staged changes."
  echo "[guard:local-paths] Use repository-relative paths instead."
  echo ""
  echo "$ABSOLUTE_HITS"
  exit 1
fi

if [[ "$use_rg" -eq 1 ]]; then
  RELATIVE_HITS="$(printf '%s\n' "$STAGED_ADDED_LINES" | rg -n -P "$RELATIVE_PATH_PATTERN" || true)"
else
  RELATIVE_HITS="$(printf '%s\n' "$STAGED_ADDED_LINES" | grep -En "$RELATIVE_PATH_PATTERN" || true)"
fi
if [[ -z "$RELATIVE_HITS" ]]; then
  exit 0
fi

if [[ "${ALLOW_RELATIVE_PATH_REFERENCES:-0}" == "1" ]]; then
  echo "[guard:local-paths] ALLOW_RELATIVE_PATH_REFERENCES=1 set; skipping confirmation."
  exit 0
fi

TMP_RELATIVE_SCAN="$(mktemp)"
printf '%s\n' "$STAGED_ADDED_LINES" > "$TMP_RELATIVE_SCAN"

RELATIVE_OUTSIDE_HITS="$(
  python3 - "$ROOT_DIR" "$TMP_RELATIVE_SCAN" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
scan_file = Path(sys.argv[2])
pattern = re.compile(r"(?<![A-Za-z0-9_])((?:\./|\.\./)[^\s\"'<>()[\]{}]+)")

def is_within_root(path: Path, repo_root: Path) -> bool:
    try:
        path.relative_to(repo_root)
        return True
    except ValueError:
        return False

lines = scan_file.read_text(encoding="utf-8").splitlines()
findings = []

for entry in lines:
    if ":" not in entry:
        continue
    file_path, content = entry.split(":", 1)
    source_file = (root / file_path).resolve()
    source_dir = source_file.parent
    for match in pattern.finditer(content):
        relative_ref = match.group(1)
        resolved_ref = (source_dir / relative_ref).resolve(strict=False)
        if not is_within_root(resolved_ref, root):
            findings.append(f"{file_path}: {relative_ref} -> {resolved_ref}")

if findings:
    print("\n".join(findings))
PY
)"

rm -f "$TMP_RELATIVE_SCAN"

if [[ -n "$RELATIVE_OUTSIDE_HITS" ]]; then
  echo "[guard:local-paths] ERROR: Relative path references escaping repo root are disallowed."
  echo "[guard:local-paths] Rewrite these as repo-root-relative paths, or set ALLOW_RELATIVE_PATH_REFERENCES=1 to bypass."
  echo ""
  echo "$RELATIVE_OUTSIDE_HITS"
  exit 1
fi

echo "[guard:local-paths] Relative path references resolve inside repo root."
