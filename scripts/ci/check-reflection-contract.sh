#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/reflaxe-rust-reflection.XXXXXX")"
semantic_out="$root_dir/test/semantic_diff/type_reflection_registry/out"

cleanup() {
	rm -rf "$tmp_root" "$semantic_out"
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

run_unsupported_case() {
	local fixture="$1"
	local operation="$2"
	local label="$3"
	local log="$tmp_root/$label.log"
	local out="$tmp_root/$label-out"

	set +e
	(cd "$root_dir/$fixture" && "$haxe_bin" compile.hxml -D "rust_output=$out") >"$log" 2>&1
	local status=$?
	set -e

	if [[ "$status" -eq 0 ]]; then
		echo "error: expected $operation to be rejected for application source" >&2
		exit 1
	fi
	grep -Fq '[HXRS-REFLECTION-UNSUPPORTED]' "$log" || {
		echo "error: missing stable reflection diagnostic for $operation" >&2
		exit 1
	}
	grep -Fq "$operation is outside the admitted reflection contract" "$log" || {
		echo "error: missing reflection contract guidance for $operation" >&2
		exit 1
	}
	grep -Eq 'Main\.hx:[0-9]+:' "$log" || {
		echo "error: $operation diagnostic is not anchored to application source" >&2
		exit 1
	}
}

cd "$root_dir"

non_reflection_out="$tmp_root/non-reflection-out"
(
	cd "$root_dir/test/snapshot/arithmetic"
	"$haxe_bin" compile.hxml -D rust_codegen_only -D rust_no_build -D "rust_output=$non_reflection_out"
)
if grep -Fq '__hx_resolve_class_name' "$non_reflection_out/src/main.rs"; then
	echo "error: an unrelated emitted program received a dead reflection registry" >&2
	exit 1
fi

python3 test/run-semantic-diff.py --case type_reflection_registry

generated_main="$semantic_out/src/main.rs"
repeat_out="$tmp_root/reflection-repeat-out"
"$haxe_bin" \
	-cp "$root_dir/test/semantic_diff/type_reflection_registry" \
	-lib reflaxe.rust \
	-D "rust_output=$repeat_out" \
	-D reflaxe_rust_profile=portable \
	-D reflaxe_rust_strict_examples \
	-D rust_no_build \
	-D reflaxe.dont_output_metadata_id \
	-D no-traces \
	-D no_traces \
	-main Main
cmp -s "$generated_main" "$repeat_out/src/main.rs" || {
	echo "error: closed reflection registry output changed between identical compilations" >&2
	exit 1
}

for helper in __hx_unsupported_reflection __hx_resolve_class_name __hx_resolve_enum_name __hx_class_name __hx_enum_name __hx_enum_constructs; do
	grep -Fq "$helper" "$generated_main" || {
		echo "error: generated reflection registry is missing $helper" >&2
		exit 1
	}
done

if grep -Eq 'todo!\(|<unknown (class|enum)>|Type\.createEmptyInstance not supported' "$generated_main"; then
	echo "error: admitted reflection output still contains a placeholder path" >&2
	exit 1
fi

unserializer_out="$tmp_root/unserializer-out"
(
	cd "$root_dir/test/snapshot/haxe_crypto_smoke"
	"$haxe_bin" compile.hxml -D rust_codegen_only -D rust_no_build -D "rust_output=$unserializer_out"
)
unserializer_rs="$unserializer_out/src/haxe_unserializer.rs"
if grep -Eq 'todo!\(|<unknown (class|enum)>|Type\.createEmptyInstance not supported' "$unserializer_rs"; then
	echo "error: framework Unserializer output still contains a reflection placeholder path" >&2
	exit 1
fi
grep -Fq 'Type.createEnum is unavailable in the current experimental dynamic-reflection path' "$unserializer_rs" || {
	echo "error: framework Unserializer no longer exposes the catchable experimental enum-construction failure" >&2
	exit 1
}

# This is deliberately an exact generated-crate check, not a source-text approximation. Upstream
# Serializer keeps a class/enum carrier statically typed as Dynamic after a runtime type guard, while
# Unserializer retains experimental construction branches. Both shapes must remain Rust-type-correct
# and warning-clean even though application-authored dynamic construction is rejected earlier.
CARGO_TARGET_DIR="$tmp_root/cargo-target" cargo check --quiet --manifest-path "$unserializer_out/Cargo.toml"

framework_out="$tmp_root/framework-failure-out"
framework_payloads="$tmp_root/framework-payloads.txt"
(
	cd "$root_dir/test/runtime_e2e/reflection_framework_failure"
	"$haxe_bin" -cp . --interp -main Main -D reflection_oracle
) >"$framework_payloads"
enum_payload="$(sed -n '1p' "$framework_payloads")"
class_payload="$(sed -n '2p' "$framework_payloads")"
if [[ -z "$enum_payload" || -z "$class_payload" ]]; then
	echo "error: Haxe reflection oracle did not produce both serialized payloads" >&2
	exit 1
fi
(
	cd "$root_dir/test/runtime_e2e/reflection_framework_failure"
	"$haxe_bin" compile.hxml -D "rust_output=$framework_out"
)
framework_stdout="$tmp_root/framework-failure.stdout"
CARGO_TARGET_DIR="$tmp_root/framework-target" cargo run --quiet --manifest-path "$framework_out/Cargo.toml" -- \
	"$enum_payload" "$class_payload" >"$framework_stdout"
cat >"$tmp_root/framework-failure.expected" <<'EOF'
enum=caught
class=caught
EOF
diff -u "$tmp_root/framework-failure.expected" "$framework_stdout"

run_unsupported_case test/negative/type_create_enum_unsupported Type.createEnum create-enum
run_unsupported_case test/negative/type_create_empty_instance_unsupported Type.createEmptyInstance create-empty-instance

echo "[reflection-contract] OK"
