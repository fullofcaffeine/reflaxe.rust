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

# CI runners may not have ripgrep; prefer it when available and fall back to grep otherwise.
use_rg=0
if [[ "${REFLAXE_NO_RG:-0}" != "1" ]] && command -v rg >/dev/null 2>&1; then
  use_rg=1
fi

match_regex() {
  local pattern="$1"
  local file="$2"
  if [[ "$use_rg" -eq 1 ]]; then
    rg -q -- "$pattern" "$file"
  else
    grep -Eq -- "$pattern" "$file"
  fi
}

match_fixed() {
  local needle="$1"
  local file="$2"
  if [[ "$use_rg" -eq 1 ]]; then
    rg -Fq -- "$needle" "$file"
  else
    grep -Fq -- "$needle" "$file"
  fi
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

assert_emitted_std_modules() {
  local crate_dir="$1"
  local main_rs="$crate_dir/src/main.rs"
  [[ -f "$main_rs" ]]
  if ! match_regex "mod haxe_ds_list;" "$main_rs"; then
    echo "error: generated main.rs is missing haxe_ds_list module import" >&2
    exit 1
  fi
  if ! match_regex "mod haxe_exception;" "$main_rs"; then
    echo "error: generated main.rs is missing haxe_exception module import" >&2
    exit 1
  fi
}

(
  cd "$app_dir"
  haxelib newrepo >/dev/null
  haxelib install "$zip_abs" --always >/dev/null
  haxe -cp . -lib reflaxe.rust -main Main -D rust_output=out -D rust_no_build
)

assert_emitted_std_modules "$app_dir/out"

if [[ -z "${CARGO_TARGET_DIR:-}" ]]; then
  export CARGO_TARGET_DIR="$root_dir/.cache/package-smoke-target"
fi
(
  cd "$app_dir/out"
  cargo build -q
)

log "compile via symlinked cwd alias (path canonicalization regression)"
alias_dir="$tmp_root/app_symlink"
ln -s "$app_dir" "$alias_dir"
verbose_log="$tmp_root/haxe-symlink-verbose.log"
(
  cd "$alias_dir"
  haxe -v -cp . -lib reflaxe.rust -main Main -D rust_output=out_symlink -D rust_no_build >"$verbose_log" 2>&1
)

if ! match_regex "^Classpath:" "$verbose_log"; then
  echo "error: verbose compile log missing classpath line for symlink regression compile" >&2
  exit 1
fi
if ! match_fixed ".haxelib/reflaxe,rust/" "$verbose_log"; then
  echo "error: verbose compile log missing reflaxe.rust haxelib classpath entry" >&2
  exit 1
fi

assert_emitted_std_modules "$app_dir/out_symlink"
(
  cd "$app_dir/out_symlink"
  cargo build -q
)

log "ok"
