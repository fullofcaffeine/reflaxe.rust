#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

clean_outputs=0
clean_cache=0
dry_run=0

usage() {
  cat <<'EOF'
Usage: scripts/ci/clean-artifacts.sh [--outputs] [--cache] [--all] [--dry-run]

Removes generated test/example artifacts and optional Cargo cache dirs.

Options:
  --outputs   Remove generated `out*` folders under `test/snapshot/*/` and `examples/*/`.
  --cache     Remove cache folders under `.cache/` used by harness scripts.
  --all       Same as `--outputs --cache`.
  --dry-run   Print what would be removed without deleting anything.
  -h, --help  Show this help text.

Defaults:
  If no explicit mode is provided, `--outputs` is assumed.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --outputs)
      clean_outputs=1
      shift
      ;;
    --cache)
      clean_cache=1
      shift
      ;;
    --all)
      clean_outputs=1
      clean_cache=1
      shift
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[clean] error: unknown arg: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$clean_outputs" -eq 0 && "$clean_cache" -eq 0 ]]; then
  clean_outputs=1
fi

paths=()

if [[ "$clean_outputs" -eq 1 ]]; then
  while IFS= read -r -d '' path; do
    paths+=("$path")
  done < <(find "$root_dir/test/snapshot" -mindepth 2 -maxdepth 2 -type d \( -name 'out' -o -name 'out_*' \) -print0 2>/dev/null || true)

  while IFS= read -r -d '' path; do
    paths+=("$path")
  done < <(find "$root_dir/examples" -mindepth 2 -maxdepth 2 -type d \( -name 'out' -o -name 'out_*' \) -print0 2>/dev/null || true)
fi

if [[ "$clean_cache" -eq 1 ]]; then
  while IFS= read -r -d '' path; do
    paths+=("$path")
  done < <(find "$root_dir/.cache" -mindepth 1 -maxdepth 1 -type d \( -name 'examples-target*' -o -name 'snapshots-target*' -o -name 'upstream-stdlib-target*' \) -print0 2>/dev/null || true)
fi

if [[ "${#paths[@]}" -eq 0 ]]; then
  echo "[clean] nothing to remove"
  exit 0
fi

removed=0
for path in "${paths[@]}"; do
  [[ -e "$path" ]] || continue
  if [[ "$dry_run" -eq 1 ]]; then
    echo "[clean] would remove: $path"
    removed=$((removed + 1))
    continue
  fi
  rm -rf "$path"
  echo "[clean] removed: $path"
  removed=$((removed + 1))
done

if [[ "$dry_run" -eq 1 ]]; then
  echo "[clean] dry-run complete ($removed path(s))"
else
  rmdir "$root_dir/.cache" 2>/dev/null || true
  echo "[clean] done ($removed path(s))"
fi
