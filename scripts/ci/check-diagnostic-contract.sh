#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/reflaxe-rust-diagnostics.XXXXXX")"

cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

haxe_bin="${HAXE_BIN:-}"
if [[ -z "$haxe_bin" ]]; then
  if [[ -x "$root_dir/node_modules/.bin/haxe" ]]; then
    haxe_bin="$root_dir/node_modules/.bin/haxe"
  else
    haxe_bin="haxe"
  fi
fi

run_error_case() {
  local fixture="$1"
  local hxml="$2"
  local id="$3"
  local trigger="$4"
  local label="$5"
  local log="$tmp_root/${label}.log"
  local out="$tmp_root/${label}-out"
  set +e
  (cd "$root_dir/$fixture" && "$haxe_bin" "$hxml" -D rust_codegen_only -D "rust_output=$out") >"$log" 2>&1
  local status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    echo "error: expected diagnostic error for $label" >&2
    exit 1
  fi
  grep -Fq "[$id]" "$log" || { echo "error: missing diagnostic id $id for $label" >&2; exit 1; }
  if grep -Eq "Warning : \\[$id\\]" "$log"; then
    echo "error: expected error severity for $id in $label" >&2
    exit 1
  fi
  grep -Eq "$trigger" "$log" || { echo "error: missing diagnostic trigger for $label" >&2; exit 1; }
}

run_warning_case() {
  local fixture="$1"
  local hxml="$2"
  local id="$3"
  local trigger="$4"
  local label="$5"
  local location="${6:-}"
  local log="$tmp_root/${label}.log"
  local out="$tmp_root/${label}-out"
  if ! (cd "$root_dir/$fixture" && "$haxe_bin" "$hxml" -D rust_no_build -D "rust_output=$out") >"$log" 2>&1; then
    echo "error: expected diagnostic warning rather than error for $label" >&2
    exit 1
  fi
  grep -Eq "Warning : \\[$id\\]" "$log" || { echo "error: missing warning severity/id $id for $label" >&2; exit 1; }
  grep -Eq "$trigger" "$log" || { echo "error: missing warning trigger for $label" >&2; exit 1; }
  if [[ -n "$location" ]] && ! grep -Eq "$location" "$log"; then
    echo "error: missing warning source anchor for $label" >&2
    exit 1
  fi
}

run_error_case test/negative/profile_removed_idiomatic compile.hxml HXRS-PROFILE-UNKNOWN 'Expected portable\|metal' profile-unknown
run_warning_case test/negative/metal_dynamic_access compile.fallback.hxml HXRS-PROFILE-CONTRACT-WARNING 'metal profile forbids haxe\.DynamicAccess' profile-warning
run_error_case test/negative/metal_no_hxrt_requires_metal compile.hxml HXRS-NO-HXRT-REQUIRES-METAL 'requires `-D reflaxe_rust_profile=metal`' no-hxrt-profile
run_error_case test/negative/metal_no_hxrt_dynamic_boundary compile.hxml HXRS-NO-HXRT-ELIGIBILITY 'reasonKind `dynamic`' no-hxrt-eligibility
run_error_case test/negative/metal_no_hxrt_runtime_boundary compile.hxml HXRS-NO-HXRT-EMITTED-RUNTIME 'generated Rust still references `hxrt`' no-hxrt-emitted
run_error_case test/negative/async_main_boundary compile.hxml HXRS-ASYNC-MAIN-SYNC '`main` must stay synchronous' async-main
run_error_case test/negative/metal_ref_alias_return_escape compile.hxml HXRS-BORROW-REGION 'returned borrow-only alias' borrow-region
run_warning_case test/negative/portable_native_import_strict compile.warn.hxml HXRS-NATIVE-IMPORT-WARNING 'portable contract imported native target modules' native-import-warning
run_error_case test/negative/portable_native_import_strict compile.hxml HXRS-NATIVE-IMPORT-ERROR 'portable contract imported native target modules' native-import-error
run_error_case test/negative/internal_hxrt_helper_import compile.hxml HXRS-INTERNAL-HELPER-IMPORT 'application code cannot import internal framework helper' internal-helper-import
run_error_case test/negative/rust_cargo_metadata_arity compile.hxml HXRS-METADATA-ARITY '`@:rustCargo` requires a single parameter' metadata-arity
run_error_case test/negative/rust_generic_metadata_value compile.hxml HXRS-METADATA-VALUE '`@:rustGeneric` must be a string or array of strings' metadata-value
run_error_case test/negative/rust_impl_invalid_trait_path compile.hxml HXRS-METADATA-VALUE 'Invalid `@:rustImpl` trait path syntax' rust-impl-trait-path
run_error_case test/negative/rust_impl_invalid_for_type compile.hxml HXRS-METADATA-VALUE 'Invalid `@:rustImpl` `forType` syntax' rust-impl-for-type
run_error_case test/negative/rust_test_metadata_placement compile.hxml HXRS-METADATA-PLACEMENT 'must live in non-main classes' metadata-placement
run_error_case test/negative/rust_cargo_structured_conflict compile.hxml HXRS-CARGO-DEPENDENCY-CONFLICT 'Conflicting `@:rustCargo` version' cargo-conflict
run_error_case test/negative/dynamic_field_assignop compile.hxml HXRS-DYNAMIC-FIELD-OPERATOR 'Decode the field to `Int`, `Float`, or `String`.*write it back explicitly' dynamic-field-assignop
run_error_case test/negative/dynamic_field_unop compile.hxml HXRS-DYNAMIC-FIELD-OPERATOR 'Decode the field to `Int`, `Float`, or `String`.*write it back explicitly' dynamic-field-unop
run_error_case test/negative/type_create_enum_unsupported compile.hxml HXRS-REFLECTION-UNSUPPORTED 'Type\.createEnum is outside the admitted reflection contract' reflection-create-enum
run_error_case test/negative/type_create_empty_instance_unsupported compile.hxml HXRS-REFLECTION-UNSUPPORTED 'Type\.createEmptyInstance is outside the admitted reflection contract' reflection-create-empty-instance
run_error_case test/negative/send_sync_borrow_capture compile.hxml HXRS-SEND-SYNC-ERROR 'captures `borrowed` with borrowed type `rust\.Ref<T>`' send-sync-error
run_warning_case test/negative/send_sync_borrow_capture compile.warn.hxml HXRS-SEND-SYNC-WARNING 'captures `borrowed` with borrowed type `rust\.Ref<T>`' send-sync-warning '^Main\.hx:[0-9]+: characters [0-9]+-[0-9]+ : Warning : \[HXRS-SEND-SYNC-WARNING\]'

echo "[diagnostic-contract-runtime] OK (identifier + severity + trigger fixtures)"
