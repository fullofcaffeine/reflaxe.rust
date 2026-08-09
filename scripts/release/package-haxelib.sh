#!/usr/bin/env bash
set -euo pipefail

if [[ "${RELEASE_STRICT_EXECUTION:-0}" != "1" ]]; then
  RELEASE_BASH_BIN="${RELEASE_BASH_BIN:-$(command -v bash)}"
  RELEASE_GIT_BIN="${RELEASE_GIT_BIN:-$(command -v git)}"
  RELEASE_HAXE_BIN="${RELEASE_HAXE_BIN:-$(command -v haxe)}"
  RELEASE_NODE_BIN="${RELEASE_NODE_BIN:-$(command -v node)}"
fi

: "${RELEASE_BASH_BIN:?reviewed release requires RELEASE_BASH_BIN}"
: "${RELEASE_GIT_BIN:?reviewed release requires RELEASE_GIT_BIN}"
: "${RELEASE_HAXE_BIN:?reviewed release requires RELEASE_HAXE_BIN}"
: "${RELEASE_NODE_BIN:?reviewed release requires RELEASE_NODE_BIN}"
if [[ "${RELEASE_STRICT_EXECUTION:-0}" = "1" ]]; then
  : "${RELEASE_TOOL_DIR:?reviewed release requires RELEASE_TOOL_DIR}"
  PATH="$RELEASE_TOOL_DIR:/usr/bin:/bin"
fi

CP_BIN=/bin/cp
DIRNAME_BIN=/usr/bin/dirname
FIND_BIN=/usr/bin/find
MKDIR_BIN=/bin/mkdir
MKTEMP_BIN=/usr/bin/mktemp
RM_BIN=/bin/rm

root_dir="$(cd "$("$DIRNAME_BIN" "${BASH_SOURCE[0]}")/../.." && pwd)"
out="${1:-dist/reflaxe.rust.zip}"
version="${2:-$("$RELEASE_NODE_BIN" -p "require('$root_dir/haxelib.json').version")}"
tag="${3:-development}"
source_sha="${4:-$("$RELEASE_GIT_BIN" -C "$root_dir" rev-parse HEAD)}"

if [[ "$out" = /* ]]; then
  out_abs="$out"
else
  out_abs="$root_dir/$out"
fi

if [ ! -x "$RELEASE_NODE_BIN" ]; then
  echo "error: RELEASE_NODE_BIN is not executable" >&2
  exit 2
fi

if [ ! -x "$RELEASE_HAXE_BIN" ]; then
  echo "error: RELEASE_HAXE_BIN is not executable" >&2
  exit 2
fi

reflaxe_run="$root_dir/vendor/reflaxe/Run.hx"
if [ ! -f "$reflaxe_run" ]; then
  echo "error: vendored Reflaxe build runner missing: vendor/reflaxe/Run.hx" >&2
  exit 2
fi

"$RELEASE_NODE_BIN" "$root_dir/scripts/ci/vendor-reflaxe-provenance.js"

"$MKDIR_BIN" -p "$("$DIRNAME_BIN" "$out_abs")"
"$RM_BIN" -f "$out_abs"

tmp="$("$MKTEMP_BIN" -d "${TMPDIR:-/tmp}/reflaxe.rust-haxelib.XXXXXX")"
cleanup() { "$RM_BIN" -rf "$tmp"; }
trap cleanup EXIT

work_dir="$tmp/work/reflaxe.rust"
build_dir="$work_dir/_Build"
"$MKDIR_BIN" -p "$work_dir"

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

  "$MKDIR_BIN" -p "$to"

  while IFS= read -r -d '' dir; do
    local rel="${dir#"$from"/}"
    if [ "$dir" = "$from" ]; then
      continue
    fi
    "$MKDIR_BIN" -p "$to/$rel"
  done < <("$FIND_BIN" "$from" -type d -print0)

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
    "$MKDIR_BIN" -p "$("$DIRNAME_BIN" "$dest")"
    "$CP_BIN" "$file" "$dest"
  done < <("$FIND_BIN" "$from" -type f -print0)
}

copy_file_required_to_work() {
  local rel="$1"
  local src="$root_dir/$rel"
  if [ ! -f "$src" ]; then
    echo "[package] error: required file missing: $rel" >&2
    exit 2
  fi
  "$MKDIR_BIN" -p "$work_dir/$("$DIRNAME_BIN" "$rel")"
  "$CP_BIN" "$src" "$work_dir/$rel"
  log "Copying file: $rel"
}

copy_file_optional_to_work() {
  local rel="$1"
  local src="$root_dir/$rel"
  if [ ! -f "$src" ]; then
    return
  fi
  "$MKDIR_BIN" -p "$work_dir/$("$DIRNAME_BIN" "$rel")"
  "$CP_BIN" "$src" "$work_dir/$rel"
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

copy_file_required_to_build_as() {
  local source_rel="$1"
  local package_rel="$2"
  local src="$root_dir/$source_rel"
  if [ ! -f "$src" ]; then
    echo "[package] error: required file missing: $source_rel" >&2
    exit 2
  fi
  "$MKDIR_BIN" -p "$build_dir/$("$DIRNAME_BIN" "$package_rel")"
  "$CP_BIN" "$src" "$build_dir/$package_rel"
  log "Copying reviewed evidence: $package_rel"
}

prune_runtime_dev_artifacts() {
  local hxrt_dir="$build_dir/runtime/hxrt"
  if [ ! -d "$hxrt_dir" ]; then
    return
  fi
  for rel in target Cargo.lock tests benches examples; do
    if [ -e "$hxrt_dir/$rel" ]; then
      "$RM_BIN" -rf "$hxrt_dir/$rel"
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
  "$RELEASE_HAXE_BIN" -cp "$root_dir/vendor/reflaxe" --run Run build _Build --deleteOldFolder "$work_dir"
)

"$RELEASE_NODE_BIN" "$root_dir/scripts/release/prepare-package-metadata.js" \
  "$build_dir/haxelib.json" \
  "$build_dir/release-metadata.json" \
  "$version" \
  "$tag" \
  "$source_sha"

"$RELEASE_NODE_BIN" "$root_dir/scripts/release/generate-license-artifacts.js" \
  --output-dir "$build_dir" \
  --version "$version"

# Package-only reviewers need the exact file-by-file Haxe source record without relying on a
# repository branch that can change after publication.
copy_file_required_to_build_as \
  "docs/stdlib-provenance-ledger.json" \
  "provenance/stdlib-provenance-ledger.json"

# Target-specific runtime/compiler assets not covered by generic Reflaxe build flow.
copy_dir_required_to_build "runtime"
prune_runtime_dev_artifacts
copy_dir_required_to_build "vendor"

"$RELEASE_NODE_BIN" "$root_dir/scripts/release/deterministic-zip.js" "$build_dir" "$out_abs"
log "wrote: $out"
