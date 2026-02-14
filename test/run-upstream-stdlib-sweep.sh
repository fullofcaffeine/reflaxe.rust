#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE_LIST="${MODULE_LIST:-$ROOT_DIR/test/upstream_std_modules.txt}"
only_module=""

HAXE_BIN="${HAXE_BIN:-}"
if [[ -z "$HAXE_BIN" ]]; then
  if [[ -x "$ROOT_DIR/node_modules/.bin/haxe" ]]; then
    HAXE_BIN="$ROOT_DIR/node_modules/.bin/haxe"
  else
    HAXE_BIN="haxe"
  fi
fi

usage() {
  cat <<'EOF'
Usage: test/run-upstream-stdlib-sweep.sh [--module MODULE] [--list PATH]

Compiles a curated set of upstream Haxe std modules with:
  -D rust_emit_upstream_std
and validates each generated crate with:
  cargo fmt + cargo check

Options:
  --module MODULE  Run only one module from the list.
  --list PATH      Module list file (default: test/upstream_std_modules.txt).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --module)
      only_module="${2:-}"
      shift 2
      ;;
    --list)
      MODULE_LIST="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown arg: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$HAXE_BIN" == */* ]]; then
  if [[ ! -x "$HAXE_BIN" ]]; then
    echo "error: haxe not found or not executable: $HAXE_BIN" >&2
    exit 2
  fi
else
  if ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
    echo "error: haxe not found in PATH (HAXE_BIN=$HAXE_BIN)" >&2
    exit 2
  fi
fi

if [[ ! -f "$MODULE_LIST" ]]; then
  echo "error: module list not found: $MODULE_LIST" >&2
  exit 2
fi

if ! command -v cargo >/dev/null 2>&1; then
  echo "error: cargo not found in PATH" >&2
  exit 2
fi

SWEEP_TARGET_BASE="${SWEEP_CARGO_TARGET_DIR:-$ROOT_DIR/.cache/upstream-stdlib-target}"
TMP_BASE="${TMPDIR:-/tmp}"
WORK_DIR="$(mktemp -d "$TMP_BASE/reflaxe-rust-upstream-std.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

SRC_DIR="$WORK_DIR/src"
mkdir -p "$SRC_DIR"
cat > "$SRC_DIR/Main.hx" <<'EOF'
class Main {
	static function main(): Void {}
}
EOF

modules=()
while IFS= read -r line; do
  module="$(printf '%s' "$line" | sed 's/[[:space:]]*#.*$//' | xargs)"
  [[ -n "$module" ]] || continue
  modules+=("$module")
done < "$MODULE_LIST"

if [[ -n "$only_module" ]]; then
  found=0
  filtered=()
  for module in "${modules[@]}"; do
    if [[ "$module" == "$only_module" ]]; then
      filtered+=("$module")
      found=1
      break
    fi
  done
  if [[ "$found" -ne 1 ]]; then
    echo "[upstream-std] error: module not present in list: $only_module" >&2
    exit 2
  fi
  modules=("${filtered[@]}")
fi

total="${#modules[@]}"
if [[ "$total" -eq 0 ]]; then
  echo "[upstream-std] error: no modules to run" >&2
  exit 2
fi

failures=()
index=0

for module in "${modules[@]}"; do
  index=$((index + 1))
  slug="${module//./_}"
  out_dir="$WORK_DIR/out/$slug"
  target_dir="$SWEEP_TARGET_BASE/$slug"
  macro_cmd="include('$module')"
  if [[ "$module" == "haxe.Json" ]]; then
    # On case-insensitive filesystems, include('haxe.Json') can collide with
    # std/haxe/json/* and trigger a false haxe.Json.Value vs haxe.json.Value error.
    # Resolve this one module by exact type lookup.
    macro_cmd="haxe.macro.Context.getType('$module')"
  fi
  mkdir -p "$out_dir"

  echo "[upstream-std] [$index/$total] $module"

  if ! "$HAXE_BIN" \
    -cp "$SRC_DIR" \
    -lib reflaxe.rust \
    -D reflaxe_rust_strict_examples \
    -D reflaxe.dont_output_metadata_id \
    -D rust_emit_upstream_std \
    -D rust_no_build \
    -D "rust_output=$out_dir" \
    -main Main \
    --macro "$macro_cmd" >/dev/null; then
    echo "[upstream-std] FAIL (haxe compile): $module" >&2
    failures+=("$module:haxe")
    continue
  fi

  if ! (cd "$out_dir" && CARGO_TARGET_DIR="$target_dir" cargo fmt >/dev/null); then
    echo "[upstream-std] FAIL (cargo fmt): $module" >&2
    failures+=("$module:fmt")
    continue
  fi

  if ! (cd "$out_dir" && CARGO_TARGET_DIR="$target_dir" cargo check -q); then
    echo "[upstream-std] FAIL (cargo check): $module" >&2
    failures+=("$module:check")
    continue
  fi
done

if [[ "${#failures[@]}" -gt 0 ]]; then
  echo "[upstream-std] failures (${#failures[@]}):" >&2
  for item in "${failures[@]}"; do
    echo "  - $item" >&2
  done
  exit 1
fi

echo "[upstream-std] ok ($total modules)"
