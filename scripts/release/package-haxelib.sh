#!/usr/bin/env bash
set -euo pipefail

out="${1:-dist/reflaxe.rust.zip}"

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out_abs="$root_dir/$out"

if ! command -v zip >/dev/null 2>&1; then
  echo "error: zip not found in PATH" >&2
  exit 2
fi

if ! command -v node >/dev/null 2>&1; then
  echo "error: node not found in PATH" >&2
  exit 2
fi

mkdir -p "$(dirname "$out_abs")"
rm -f "$out_abs"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/reflaxe.rust-haxelib.XXXXXX")"
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT

pkg_dir="$tmp/package"
mkdir -p "$pkg_dir"

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

copy_file_required() {
  local rel="$1"
  local src="$root_dir/$rel"
  if [ ! -f "$src" ]; then
    echo "[package] error: required file missing: $rel" >&2
    exit 2
  fi
  mkdir -p "$pkg_dir/$(dirname "$rel")"
  cp "$src" "$pkg_dir/$rel"
  log "Copying file: $rel"
}

copy_file_optional() {
  local rel="$1"
  local src="$root_dir/$rel"
  if [ ! -f "$src" ]; then
    return
  fi
  mkdir -p "$pkg_dir/$(dirname "$rel")"
  cp "$src" "$pkg_dir/$rel"
  log "Copying file: $rel"
}

copy_dir_required() {
  local rel="$1"
  local src="$root_dir/$rel"
  if [ ! -d "$src" ]; then
    echo "[package] error: required directory missing: $rel" >&2
    exit 2
  fi
  copy_tree_content "$src" "$pkg_dir/$rel"
  log "Copying directory: $rel/"
}

prune_runtime_dev_artifacts() {
  local hxrt_dir="$pkg_dir/runtime/hxrt"
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

lib_meta_file="$tmp/lib-meta.txt"
(cd "$root_dir" && node <<'NODE'
const fs = require("fs");
const data = JSON.parse(fs.readFileSync("haxelib.json", "utf8"));
if (!data.classPath || typeof data.classPath !== "string") {
  console.error('error: "classPath" must be defined in haxelib.json');
  process.exit(2);
}
console.log(data.classPath);
const stdPaths = (data.reflaxe && Array.isArray(data.reflaxe.stdPaths)) ? data.reflaxe.stdPaths : [];
for (const p of stdPaths) console.log(p);
NODE
) > "$lib_meta_file"

class_path=""
std_paths=()
line_index=0
while IFS= read -r line || [ -n "$line" ]; do
  if [ "$line_index" -eq 0 ]; then
    class_path="$line"
  else
    std_paths+=("$line")
  fi
  line_index=$((line_index + 1))
done < "$lib_meta_file"

if [ -z "$class_path" ]; then
  echo "[package] error: failed to parse haxelib.json metadata" >&2
  exit 2
fi
class_path_src="$root_dir/$class_path"
class_path_dest="$pkg_dir/$class_path"

copy_tree_content "$class_path_src" "$class_path_dest"
log "Copying class path: $(strip_trailing_slashes "$class_path")/"

for std_path in "${std_paths[@]}"; do
  [ -z "$std_path" ] && continue
  std_src="$root_dir/$std_path"
  std_trimmed="$(strip_trailing_slashes "$std_path")"
  replace_ext=""
  if [[ "$std_trimmed" == *_std ]]; then
    replace_ext=".cross.hx"
  fi
  copy_tree_content "$std_src" "$class_path_dest" "$replace_ext"
  log "Copying std path into class path: ${std_trimmed}/"
done

# Target-specific runtime/compiler assets not covered by generic Reflaxe build flow.
copy_dir_required "runtime"
prune_runtime_dev_artifacts
copy_dir_required "vendor"

# Reflaxe build parity files.
copy_file_required "LICENSE"
copy_file_required "README.md"
copy_file_required "extraParams.hxml"
copy_file_optional "Run.hx"
copy_file_optional "run.n"

# Copy and sanitize haxelib.json.
node - "$root_dir/haxelib.json" "$pkg_dir/haxelib.json" <<'NODE'
const fs = require("fs");
const [src, dest] = process.argv.slice(2);
const data = JSON.parse(fs.readFileSync(src, "utf8"));
if (Object.prototype.hasOwnProperty.call(data, "reflaxe")) {
  delete data.reflaxe;
}
fs.writeFileSync(dest, JSON.stringify(data, null, "\t") + "\n");
NODE
log "Copying and sanitizing haxelib.json"

(cd "$pkg_dir" && zip -r -X "$out_abs" . >/dev/null)
log "wrote: $out"
