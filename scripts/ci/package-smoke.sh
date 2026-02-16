#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root_dir"

log() {
  printf '[package-smoke] %s\n' "$*"
}

is_truthy() {
  local value="${1:-}"
  case "$value" in
    1|true|TRUE|yes|YES|on|ON)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

tmp_root=""

cleanup() {
  local original_exit="${1:-0}"
  if [[ -z "$tmp_root" || ! -d "$tmp_root" ]]; then
    return "$original_exit"
  fi
  if is_truthy "${KEEP_ARTIFACTS:-0}"; then
    log "keep artifacts enabled (KEEP_ARTIFACTS=1)"
    return "$original_exit"
  fi
  rm -rf "$tmp_root"
  return "$original_exit"
}

trap 'cleanup $?' EXIT

zip_rel="${PACKAGE_ZIP_REL:-dist/reflaxe.rust-audit.zip}"
zip_abs="$root_dir/$zip_rel"

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/reflaxe-rust-package-smoke.XXXXXX")"
pkg_dir="$tmp_root/package"
app_dir="$tmp_root/app"

log "build package zip"
rm -f "$zip_abs"
bash scripts/release/package-haxelib.sh "$zip_rel"

if [[ ! -f "$zip_abs" ]]; then
  echo "error: package zip was not created: $zip_rel" >&2
  exit 2
fi

mkdir -p "$pkg_dir" "$app_dir"
unzip -q "$zip_abs" -d "$pkg_dir"

log "verify package layout"
[[ -f "$pkg_dir/haxelib.json" ]]
[[ -d "$pkg_dir/src" ]]
[[ -d "$pkg_dir/runtime/hxrt" ]]
[[ -d "$pkg_dir/vendor/reflaxe/src" ]]
[[ -f "$pkg_dir/src/reflaxe/rust/CompilerInit.hx" ]]
[[ -f "$pkg_dir/src/haxe/Exception.cross.hx" ]]
[[ -f "$pkg_dir/src/haxe/ds/List.cross.hx" ]]

if [[ -d "$pkg_dir/std" ]]; then
  echo "error: package unexpectedly contains top-level std/ (std paths should be flattened into src/)" >&2
  exit 2
fi

if [[ -e "$pkg_dir/runtime/hxrt/target" || -e "$pkg_dir/runtime/hxrt/tests" ]]; then
  echo "error: package contains runtime dev artifacts under runtime/hxrt/" >&2
  exit 2
fi

node - "$pkg_dir/haxelib.json" <<'NODE'
const fs = require("fs");
const file = process.argv[2];
const data = JSON.parse(fs.readFileSync(file, "utf8"));
if (Object.prototype.hasOwnProperty.call(data, "reflaxe")) {
  console.error("error: packaged haxelib.json still contains `reflaxe` metadata");
  process.exit(2);
}
if (data.classPath !== "src") {
  console.error(`error: packaged classPath must be \"src\" (found: ${String(data.classPath)})`);
  process.exit(2);
}
NODE

log "compile via isolated local haxelib repo"
cat > "$app_dir/Main.hx" <<'HX'
class Main {
  static function main() {
    var list = new haxe.ds.List<Int>();
    list.add(1);
    trace(list.length);
  }
}
HX

(
  cd "$app_dir"
  haxelib newrepo >/dev/null
  haxelib install "$zip_abs" --always >/dev/null
  haxe -cp . -lib reflaxe.rust -main Main -D rust_output=out -D rust_no_build
)

[[ -f "$app_dir/out/src/main.rs" ]]
if ! rg -q "mod haxe_ds_list;" "$app_dir/out/src/main.rs"; then
  echo "error: generated main.rs is missing haxe_ds_list module import" >&2
  exit 1
fi
if ! rg -q "mod haxe_exception;" "$app_dir/out/src/main.rs"; then
  echo "error: generated main.rs is missing haxe_exception module import" >&2
  exit 1
fi

if [[ -z "${CARGO_TARGET_DIR:-}" ]]; then
  export CARGO_TARGET_DIR="$root_dir/.cache/package-smoke-target"
fi
(
  cd "$app_dir/out"
  cargo build -q
)

log "ok"
