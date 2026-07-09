#!/usr/bin/env bash
set -euo pipefail

out="${1:-dist/reflaxe.rust.zip}"

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out_abs="$root_dir/$out"

if ! command -v zip >/dev/null 2>&1; then
  echo "error: zip not found in PATH" >&2
  exit 2
fi

if ! command -v haxe >/dev/null 2>&1; then
  echo "error: haxe not found in PATH" >&2
  exit 2
fi

reflaxe_run="$root_dir/vendor/reflaxe/Run.hx"
if [ ! -f "$reflaxe_run" ]; then
  echo "error: vendored Reflaxe build runner missing: vendor/reflaxe/Run.hx" >&2
  exit 2
fi

mkdir -p "$(dirname "$out_abs")"
rm -f "$out_abs"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/reflaxe.rust-haxelib.XXXXXX")"
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT

work_dir="$tmp/work/reflaxe.rust"
build_dir="$work_dir/_Build"
mkdir -p "$work_dir"

log() {
  echo "[package] $*"
}

strip_trailing_slashes() {
  local p="$1"
  while [[ "$p" != "/" && "$p" == */ ]]; do
    p="${p%/}"
  done
  printf '%s' "$p"
}

copy_tree_content() {
  local from_raw="$1"
  local to_raw="$2"
  local replace_ext="${3:-}"
  local from to
  from="$(strip_trailing_slashes "$from_raw")"
  to="$(strip_trailing_slashes "$to_raw")"

  if [ ! -d "$from" ]; then
    echo "[package] error: source directory does not exist: $from" >&2
    exit 2
  fi

  mkdir -p "$to"

  while IFS= read -r -d '' dir; do
    local rel="${dir#"$from"/}"
    if [ "$dir" = "$from" ]; then
      continue
    fi
    mkdir -p "$to/$rel"
  done < <(find "$from" -type d -print0)

  while IFS= read -r -d '' file; do
    local rel="${file#"$from"/}"
    local dest="$to/$rel"
    if [ -n "$replace_ext" ]; then
      local base="${dest%.*}"
      if [ "$base" = "$dest" ]; then
        dest="${dest}${replace_ext}"
      else
        dest="${base}${replace_ext}"
      fi
    fi
    mkdir -p "$(dirname "$dest")"
    cp "$file" "$dest"
  done < <(find "$from" -type f -print0)
}

copy_file_required_to_work() {
  local rel="$1"
  local src="$root_dir/$rel"
  if [ ! -f "$src" ]; then
    echo "[package] error: required file missing: $rel" >&2
    exit 2
  fi
  mkdir -p "$work_dir/$(dirname "$rel")"
  cp "$src" "$work_dir/$rel"
  log "Copying file: $rel"
}

copy_file_optional_to_work() {
  local rel="$1"
  local src="$root_dir/$rel"
  if [ ! -f "$src" ]; then
    return
  fi
  mkdir -p "$work_dir/$(dirname "$rel")"
  cp "$src" "$work_dir/$rel"
  log "Copying file: $rel"
}

copy_dir_required_to_work() {
  local rel="$1"
  local src="$root_dir/$rel"
  if [ ! -d "$src" ]; then
    echo "[package] error: required directory missing: $rel" >&2
    exit 2
  fi
  copy_tree_content "$src" "$work_dir/$rel"
  log "Copying directory: $rel/"
}

copy_dir_required_to_build() {
  local rel="$1"
  local src="$root_dir/$rel"
  if [ ! -d "$src" ]; then
    echo "[package] error: required directory missing: $rel" >&2
    exit 2
  fi
  copy_tree_content "$src" "$build_dir/$rel"
  log "Copying directory: $rel/"
}

prune_runtime_dev_artifacts() {
  local hxrt_dir="$build_dir/runtime/hxrt"
  if [ ! -d "$hxrt_dir" ]; then
    return
  fi
  for rel in target Cargo.lock tests benches examples; do
    if [ -e "$hxrt_dir/$rel" ]; then
      rm -rf "$hxrt_dir/$rel"
      log "Pruning runtime dev artifact: runtime/hxrt/$rel"
    fi
  done
}

copy_dir_required_to_work "src"
copy_dir_required_to_work "std"
copy_file_required_to_work "haxelib.json"
copy_file_required_to_work "extraParams.hxml"
copy_file_required_to_work "LICENSE"
copy_file_required_to_work "README.md"
copy_file_optional_to_work "Run.hx"
copy_file_optional_to_work "run.n"

(
  cd "$work_dir"
  log "Running Reflaxe build into _Build/"
  haxe -cp "$root_dir/vendor/reflaxe" --run Run build _Build --deleteOldFolder "$work_dir"
)

# Target-specific runtime/compiler assets not covered by generic Reflaxe build flow.
copy_dir_required_to_build "runtime"
prune_runtime_dev_artifacts
copy_dir_required_to_build "vendor"

(cd "$build_dir" && zip -r -X "$out_abs" . >/dev/null)
log "wrote: $out"
