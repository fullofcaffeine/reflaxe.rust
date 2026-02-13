#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

clean_outputs=0
clean_cache=0
dry_run=0

# Retry knobs help with transient teardown races (especially on Windows/Cargo).
rm_retries="${CLEAN_ARTIFACTS_RM_RETRIES:-6}"
rm_retry_sleep="${CLEAN_ARTIFACTS_RM_RETRY_SLEEP:-1}"

display_path() {
  local path="$1"
  if [[ "$path" == "$root_dir/"* ]]; then
    printf ".%s\n" "${path#$root_dir}"
    return 0
  fi
  printf "%s\n" "$path"
}

usage() {
  cat <<'EOUSAGE'
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
EOUSAGE
}

remove_with_retry() {
  local path="$1"
  local shown_path
  local attempt

  shown_path="$(display_path "$path")"

  for ((attempt = 1; attempt <= rm_retries; attempt++)); do
    [[ -e "$path" ]] || return 0

    if rm -rf "$path" 2>/dev/null; then
      return 0
    fi

    # Allow slow child-process teardown to complete before retrying.
    sleep "$rm_retry_sleep"
  done

  [[ -e "$path" ]] || return 0
  echo "[clean] WARN: failed to remove after ${rm_retries} attempts: $shown_path" >&2
  return 1
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

# Deduplicate and remove deeper/longer paths first for parent/child safety.
sorted_paths=()
while IFS= read -r sorted_path; do
  [[ -n "$sorted_path" ]] || continue
  sorted_paths+=("$sorted_path")
done < <(
  printf '%s\n' "${paths[@]}" \
    | awk '!seen[$0]++' \
    | awk '{ printf "%06d %s\n", length($0), $0 }' \
    | sort -rn \
    | cut -d' ' -f2-
)
paths=("${sorted_paths[@]}")

removed=0
failed=0
for path in "${paths[@]}"; do
  [[ -e "$path" ]] || continue
  shown_path="$(display_path "$path")"
  if [[ "$dry_run" -eq 1 ]]; then
    echo "[clean] would remove: $shown_path"
    removed=$((removed + 1))
    continue
  fi

  if remove_with_retry "$path"; then
    echo "[clean] removed: $shown_path"
    removed=$((removed + 1))
  else
    failed=$((failed + 1))
  fi
done

if [[ "$dry_run" -eq 1 ]]; then
  echo "[clean] dry-run complete ($removed path(s))"
  exit 0
fi

rmdir "$root_dir/.cache" 2>/dev/null || true

echo "[clean] done ($removed path(s))"
if [[ "$failed" -gt 0 ]]; then
  echo "[clean] WARN: $failed path(s) could not be removed" >&2
  exit 1
fi
