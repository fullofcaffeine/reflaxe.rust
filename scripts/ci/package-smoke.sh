#!/usr/bin/env bash
set -euo pipefail

if [[ "${RELEASE_STRICT_EXECUTION:-0}" != "1" ]]; then
  RELEASE_BASH_BIN="${RELEASE_BASH_BIN:-$(command -v bash)}"
  RELEASE_CARGO_BIN="${RELEASE_CARGO_BIN:-$(command -v cargo)}"
  RELEASE_GIT_BIN="${RELEASE_GIT_BIN:-$(command -v git)}"
  RELEASE_HAXE_BIN="${RELEASE_HAXE_BIN:-$(command -v haxe)}"
  RELEASE_HAXELIB_BIN="${RELEASE_HAXELIB_BIN:-$(command -v haxelib)}"
  RELEASE_NODE_BIN="${RELEASE_NODE_BIN:-$(command -v node)}"
fi

: "${RELEASE_BASH_BIN:?package smoke requires RELEASE_BASH_BIN}"
: "${RELEASE_CARGO_BIN:?package smoke requires RELEASE_CARGO_BIN}"
: "${RELEASE_GIT_BIN:?package smoke requires RELEASE_GIT_BIN}"
: "${RELEASE_HAXE_BIN:?package smoke requires RELEASE_HAXE_BIN}"
: "${RELEASE_HAXELIB_BIN:?package smoke requires RELEASE_HAXELIB_BIN}"
: "${RELEASE_NODE_BIN:?package smoke requires RELEASE_NODE_BIN}"
if [[ "${RELEASE_STRICT_EXECUTION:-0}" = "1" ]]; then
  : "${RELEASE_TOOL_DIR:?package smoke requires RELEASE_TOOL_DIR}"
  PATH="$RELEASE_TOOL_DIR:/usr/bin:/bin"
fi

CAT_BIN=/bin/cat
DIFF_BIN=/usr/bin/diff
DIRNAME_BIN=/usr/bin/dirname
GREP_BIN=/usr/bin/grep
LN_BIN=/bin/ln
MKDIR_BIN=/bin/mkdir
MKTEMP_BIN=/usr/bin/mktemp
RM_BIN=/bin/rm
UNZIP_BIN=/usr/bin/unzip

root_dir="$(cd "$("$DIRNAME_BIN" "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root_dir"
tracked_before="$("$RELEASE_GIT_BIN" status --porcelain --untracked-files=no)"

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

match_regex() {
  local pattern="$1"
  local file="$2"
  "$GREP_BIN" -Eq -- "$pattern" "$file"
}

match_fixed() {
  local needle="$1"
  local file="$2"
  "$GREP_BIN" -Fq -- "$needle" "$file"
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
  "$RM_BIN" -rf "$tmp_root"
  return "$original_exit"
}

trap 'cleanup $?' EXIT

zip_rel="${PACKAGE_ZIP_REL:-dist/reflaxe.rust-audit.zip}"
zip_abs="$root_dir/$zip_rel"

tmp_root="$("$MKTEMP_BIN" -d "${TMPDIR:-/tmp}/reflaxe-rust-package-smoke.XXXXXX")"
pkg_dir="$tmp_root/package"
app_dir="$tmp_root/app"
source_app_dir="$tmp_root/app_source"

log "build package zip"
if is_truthy "${PACKAGE_SMOKE_USE_EXISTING:-0}"; then
  log "using existing package zip: $zip_rel"
else
  "$RM_BIN" -f "$zip_abs"
  "$RELEASE_BASH_BIN" scripts/release/package-haxelib.sh "$zip_rel"
fi

if [[ ! -f "$zip_abs" ]]; then
  echo "error: package zip was not created: $zip_rel" >&2
  exit 2
fi

"$MKDIR_BIN" -p "$pkg_dir" "$app_dir" "$source_app_dir"
"$UNZIP_BIN" -q "$zip_abs" -d "$pkg_dir"

write_smoke_main() {
  local dest_dir="$1"
  "$CAT_BIN" > "$dest_dir/Main.hx" <<'HX'
class Main {
  static function main() {
    var list = new haxe.ds.List<Int>();
    list.add(1);
    try {
      throw new haxe.Exception("package smoke");
    } catch (e:haxe.Exception) {
      trace(e.message);
    }
    Sys.println("package smoke");
    trace(list.length);
  }
}
HX
}

write_support_crate_plan_main() {
  local dest_dir="$1"
  "$CAT_BIN" > "$dest_dir/SupportCratePlanMain.hx" <<'HX'
@:native("demo_support::Api")
@:rustSupportCrate({
  name: "demo_support",
  sourceRoot: "native/demo_support",
  unsafePolicy: "forbid",
  targets: ["*"],
  dependencies: []
})
extern class DemoSupportApi {}

class SupportCratePlanMain {
  static function main() {}
}
HX
}

log "verify package layout"
[[ -f "$pkg_dir/haxelib.json" ]]
[[ -d "$pkg_dir/src" ]]
[[ -d "$pkg_dir/runtime/hxrt" ]]
[[ -d "$pkg_dir/vendor/reflaxe/src" ]]
[[ -f "$pkg_dir/THIRD_PARTY_NOTICES.md" ]]
[[ -f "$pkg_dir/release-sbom.json" ]]
[[ -f "$pkg_dir/vendor/reflaxe/LICENSE" ]]
[[ -f "$pkg_dir/vendor/reflaxe/provenance.json" ]]
[[ -f "$pkg_dir/vendor/reflaxe/reflaxe-rust.patch" ]]
[[ -f "$pkg_dir/provenance/stdlib-provenance-ledger.json" ]]
[[ -f "$pkg_dir/src/reflaxe/rust/CompilerInit.hx" ]]
[[ -f "$pkg_dir/src/haxe/Exception.cross.hx" ]]
[[ -f "$pkg_dir/src/haxe/ds/List.cross.hx" ]]
[[ -f "$pkg_dir/src/rust/Option.hx" ]]
[[ ! -d "$pkg_dir/src/rust/_std" ]]

if [[ -d "$pkg_dir/std" ]]; then
  echo "error: package unexpectedly contains top-level std/ (std paths should be flattened into src/)" >&2
  exit 2
fi

if [[ -e "$pkg_dir/runtime/hxrt/target" || -e "$pkg_dir/runtime/hxrt/tests" ]]; then
  echo "error: package contains runtime dev artifacts under runtime/hxrt/" >&2
  exit 2
fi

"$RELEASE_NODE_BIN" - "$pkg_dir/haxelib.json" <<'NODE'
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
write_smoke_main "$app_dir"

assert_emitted_std_modules() {
  local crate_dir="$1"
  local main_rs="$crate_dir/src/main.rs"
  local call_stack_rs="$crate_dir/src/haxe_call_stack_call_stack_impl_.rs"
  [[ -f "$main_rs" ]]
  [[ -f "$call_stack_rs" ]]
  if ! match_regex "mod haxe_ds_list;" "$main_rs"; then
    echo "error: generated main.rs is missing haxe_ds_list module import" >&2
    exit 1
  fi
  if ! match_regex "mod haxe_exception;" "$main_rs"; then
    echo "error: generated main.rs is missing haxe_exception module import" >&2
    exit 1
  fi
  if ! match_fixed "e: crate::HxRef<crate::haxe_exception::Exception>" "$call_stack_rs"; then
    echo "error: generated CallStackImpl.exception_to_string lost the typed haxe.Exception contract" >&2
    exit 1
  fi
  if match_fixed "exception_to_string(e: Exception)" "$call_stack_rs"; then
    echo "error: generated CallStackImpl.exception_to_string emitted a bare Exception type" >&2
    exit 1
  fi
}

log "compile source layout via reviewed checkout roots"
write_smoke_main "$source_app_dir"
(
  cd "$root_dir"
  # The reviewed release executable is the raw Haxe binary, not the Lix shim that expands
  # HAXE_LIBRARY_PATH. Pass the source checkout roots explicitly so this gate cannot fall back to
  # an ambient Haxelib installation or miss the target std overrides before typing starts.
  "$RELEASE_HAXE_BIN" \
    -cp "$source_app_dir" \
    -cp "$root_dir/src" \
    -cp "$root_dir/std" \
    -cp "$root_dir/std/rust/_std" \
    -cp "$root_dir/vendor/reflaxe/src" \
    -D reflaxe=4.0.0-beta \
    -D reflaxe.rust=0.0.0-development \
    --macro 'nullSafety("reflaxe.rust")' \
    --macro 'reflaxe.rust.CompilerBootstrap.Start()' \
    --macro 'reflaxe.rust.CompilerInit.Start()' \
    -main Main \
    -D rust_output="$source_app_dir/out_source" \
    -D rust_no_build
)

assert_emitted_std_modules "$source_app_dir/out_source"

(
  cd "$app_dir"
  "$RELEASE_HAXELIB_BIN" newrepo >/dev/null
  "$RELEASE_HAXELIB_BIN" install "$zip_abs" --always >/dev/null
  "$RELEASE_NODE_BIN" - "$root_dir/.haxerc" "$app_dir/.haxerc" <<'NODE'
const fs = require('fs')
const [sourcePath, outputPath] = process.argv.slice(2)
const source = JSON.parse(fs.readFileSync(sourcePath, 'utf8'))
if (typeof source.version !== 'string' || !/^\d+\.\d+\.\d+$/.test(source.version)) {
  throw new Error('reviewed project .haxerc lacks an exact Haxe version')
}
fs.writeFileSync(
  outputPath,
  `${JSON.stringify({ version: source.version, resolveLibs: 'haxelib' }, null, 2)}\n`
)
NODE
  "$RELEASE_HAXE_BIN" -cp . -lib reflaxe.rust -main Main -D rust_output=out -D rust_no_build
)

assert_emitted_std_modules "$app_dir/out"

log "verify packaged support-crate declaration planner"
write_support_crate_plan_main "$app_dir"
support_crate_log="$tmp_root/support-crate-plan.log"
if (
  cd "$app_dir"
  "$RELEASE_HAXE_BIN" -cp . -lib reflaxe.rust -main SupportCratePlanMain -D rust_output=out_support_crate -D rust_no_build
) >"$support_crate_log" 2>&1; then
  echo "error: packaged support-crate declaration unexpectedly compiled" >&2
  exit 1
fi
if ! match_fixed "[HXRS-SUPPORT-CRATE-SOURCE-ADMISSION-UNAVAILABLE]" "$support_crate_log"; then
  echo "error: packaged compiler did not report the stable support-crate source-admission diagnostic" >&2
  "$CAT_BIN" "$support_crate_log" >&2
  exit 1
fi
if [[ -e "$app_dir/out_support_crate" ]]; then
  echo "error: packaged support-crate declaration created Rust output before source admission" >&2
  exit 1
fi

if [[ -z "${CARGO_TARGET_DIR:-}" ]]; then
  export CARGO_TARGET_DIR="$root_dir/.cache/package-smoke-target"
fi

(
  cd "$source_app_dir/out_source"
  "$RELEASE_CARGO_BIN" build -q
)

(
  cd "$app_dir/out"
  "$RELEASE_CARGO_BIN" build -q
)

log "compile via symlinked cwd alias (path canonicalization regression)"
alias_dir="$tmp_root/app_symlink"
"$LN_BIN" -s "$app_dir" "$alias_dir"
verbose_log="$tmp_root/haxe-symlink-verbose.log"
(
  cd "$alias_dir"
  "$RELEASE_HAXE_BIN" -v -cp . -lib reflaxe.rust -main Main -D rust_output=out_symlink -D rust_no_build >"$verbose_log" 2>&1
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
  "$RELEASE_CARGO_BIN" build -q
)

tracked_after="$("$RELEASE_GIT_BIN" status --porcelain --untracked-files=no)"
if [[ "$tracked_after" != "$tracked_before" ]]; then
  echo "error: package smoke modified tracked repository files" >&2
  "$DIFF_BIN" <(printf '%s\n' "$tracked_before") <(printf '%s\n' "$tracked_after") >&2 || true
  exit 2
fi

log "ok"
