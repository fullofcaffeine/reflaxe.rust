#!/usr/bin/env bash
set -euo pipefail

script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
invocation_dir="$(pwd)"
cd "$root_dir"

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/dev/watch-haxe-rust.sh --hxml <path> [options]

Options:
  --hxml <path>         Required. Path to the hxml file.
  --mode <run|build|test>
                        Action per rebuild. Default: run.
  --watch <path>        Extra watch root (repeatable).
  --debounce-ms <n>     Watch debounce in milliseconds. Default: 250.
  --haxe-bin <path>     Haxe binary. Default: $HAXE_BIN or haxe.
  --cargo-bin <path>    Cargo binary. Default: $CARGO_BIN or cargo.
  --once                Run one cycle without watching.
  -h, --help            Show this help.

Examples:
  npm run dev:watch -- --hxml examples/hello/compile.hxml
  npm run dev:watch -- --hxml examples/hello/compile.hxml --mode test
  npm run dev:watch -- --hxml examples/hello/compile.hxml --once
USAGE
}

fail() {
  echo "error: $*" >&2
  exit 2
}

display_path() {
  local input="$1"
  if [[ "$input" == "$root_dir" ]]; then
    printf ".\n"
  elif [[ "$input" == "$root_dir/"* ]]; then
    printf "%s\n" "${input#"$root_dir/"}"
  else
    printf "[external:%s]\n" "$(basename "$input")"
  fi
}

normalize_existing_path() {
  local input="$1"
  if [[ -d "$input" ]]; then
    (cd "$input" && pwd)
  elif [[ -f "$input" ]]; then
    printf "%s/%s\n" "$(cd "$(dirname "$input")" && pwd)" "$(basename "$input")"
  else
    fail "path does not exist: $(display_path "$input")"
  fi
}

resolve_path_from_base() {
  local input="$1"
  local base="$2"
  if [[ "$input" == /* ]]; then
    printf "%s\n" "$input"
  else
    printf "%s/%s\n" "$base" "$input"
  fi
}

extract_rust_output() {
  awk '
    function trim(v) {
      sub(/^[ \t]+/, "", v)
      sub(/[ \t]+$/, "", v)
      return v
    }
    {
      line = $0
      sub(/[ \t]*#.*/, "", line)
      line = trim(line)
      if (line == "") {
        next
      }

      if (line ~ /^-D[ \t]+rust_output=/) {
        sub(/^-D[ \t]+rust_output=/, "", line)
        print trim(line)
        exit
      }

      if (line ~ /^-D[ \t]+rust_output[ \t]+/) {
        sub(/^-D[ \t]+rust_output[ \t]+/, "", line)
        print trim(line)
        exit
      }
    }
  ' "$hxml_abs"
}

extract_class_paths() {
  awk '
    function trim(v) {
      sub(/^[ \t]+/, "", v)
      sub(/[ \t]+$/, "", v)
      return v
    }
    {
      line = $0
      sub(/[ \t]*#.*/, "", line)
      line = trim(line)
      if (line == "") {
        next
      }

      if (line ~ /^-cp[ \t]+/) {
        sub(/^-cp[ \t]+/, "", line)
        print trim(line)
        next
      }

      if (line ~ /^--class-path[ \t]+/) {
        sub(/^--class-path[ \t]+/, "", line)
        print trim(line)
        next
      }

      if (line ~ /^--class-path=/) {
        sub(/^--class-path=/, "", line)
        print trim(line)
      }
    }
  ' "$hxml_abs"
}

mode="run"
debounce_ms="${HAXE_RUST_WATCH_DEBOUNCE_MS:-250}"
hxml_arg=""
once=0
haxe_bin="${HAXE_BIN:-haxe}"
cargo_bin="${CARGO_BIN:-cargo}"
declare -a extra_watch_paths=()
declare -a watch_paths=()
declare -a ignore_paths=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hxml)
      [[ $# -ge 2 ]] || fail "--hxml requires a value"
      hxml_arg="$2"
      shift 2
      ;;
    --mode)
      [[ $# -ge 2 ]] || fail "--mode requires a value"
      mode="$2"
      shift 2
      ;;
    --watch)
      [[ $# -ge 2 ]] || fail "--watch requires a value"
      extra_watch_paths+=("$2")
      shift 2
      ;;
    --debounce-ms)
      [[ $# -ge 2 ]] || fail "--debounce-ms requires a value"
      debounce_ms="$2"
      shift 2
      ;;
    --haxe-bin)
      [[ $# -ge 2 ]] || fail "--haxe-bin requires a value"
      haxe_bin="$2"
      shift 2
      ;;
    --cargo-bin)
      [[ $# -ge 2 ]] || fail "--cargo-bin requires a value"
      cargo_bin="$2"
      shift 2
      ;;
    --once)
      once=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

[[ -n "$hxml_arg" ]] || fail "missing required --hxml <path>"
case "$mode" in
  run|build|test) ;;
  *) fail "invalid --mode '$mode' (expected: run, build, or test)" ;;
esac
[[ "$debounce_ms" =~ ^[0-9]+$ ]] || fail "--debounce-ms must be a non-negative integer"

if [[ "$hxml_arg" == /* && -f "$hxml_arg" ]]; then
  hxml_abs="$(normalize_existing_path "$hxml_arg")"
elif [[ -f "$invocation_dir/$hxml_arg" ]]; then
  hxml_abs="$(normalize_existing_path "$invocation_dir/$hxml_arg")"
elif [[ -f "$root_dir/$hxml_arg" ]]; then
  hxml_abs="$(normalize_existing_path "$root_dir/$hxml_arg")"
else
  fail "hxml file not found: $hxml_arg"
fi

hxml_dir="$(dirname "$hxml_abs")"
hxml_file="$(basename "$hxml_abs")"
rust_output_rel="$(extract_rust_output || true)"
rust_output_abs=""
if [[ -n "$rust_output_rel" ]]; then
  rust_output_abs="$(resolve_path_from_base "$rust_output_rel" "$hxml_dir")"
fi

if [[ "$mode" != "build" && -z "$rust_output_abs" ]]; then
  fail "missing '-D rust_output=...' in $(display_path "$hxml_abs"), required for mode '$mode'"
fi

run_cycle() {
  echo "[watch] compiling $(display_path "$hxml_abs")"
  (cd "$hxml_dir" && "$haxe_bin" "$hxml_file")

  case "$mode" in
    build)
      ;;
    run)
      if [[ ! -f "$rust_output_abs/Cargo.toml" ]]; then
        fail "Cargo.toml not found in $(display_path "$rust_output_abs") after compile"
      fi
      echo "[watch] cargo run ($(display_path "$rust_output_abs"))"
      (cd "$rust_output_abs" && "$cargo_bin" run -q)
      ;;
    test)
      if [[ ! -f "$rust_output_abs/Cargo.toml" ]]; then
        fail "Cargo.toml not found in $(display_path "$rust_output_abs") after compile"
      fi
      echo "[watch] cargo test ($(display_path "$rust_output_abs"))"
      (cd "$rust_output_abs" && "$cargo_bin" test -q)
      ;;
  esac
}

if [[ "$once" -eq 1 ]]; then
  run_cycle
  exit $?
fi

if ! command -v watchexec >/dev/null 2>&1; then
  cat <<INSTALL
error: watchexec is required for watch mode.

Install options:
  - Homebrew: brew install watchexec
  - Cargo:    cargo install watchexec-cli

Tip: run a single cycle without watchexec:
  bash scripts/dev/watch-haxe-rust.sh --hxml $(display_path "$hxml_abs") --once --mode $mode
INSTALL
  exit 127
fi

path_in_watch_paths() {
  local target="$1"
  local existing
  for existing in "${watch_paths[@]}"; do
    if [[ "$existing" == "$target" ]]; then
      return 0
    fi
  done
  return 1
}

path_in_ignore_paths() {
  local target="$1"
  local existing
  for existing in "${ignore_paths[@]}"; do
    if [[ "$existing" == "$target" ]]; then
      return 0
    fi
  done
  return 1
}

add_watch_path() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    return
  fi

  local normalized
  normalized="$(normalize_existing_path "$path")"
  if ! path_in_watch_paths "$normalized"; then
    watch_paths+=("$normalized")
  fi
}

add_ignore_path() {
  local path="$1"
  if [[ -z "$path" ]]; then
    return
  fi
  if ! path_in_ignore_paths "$path"; then
    ignore_paths+=("$path")
  fi
}

add_watch_path "$hxml_abs"
add_watch_path "$hxml_dir"
while IFS= read -r class_path; do
  [[ -n "$class_path" ]] || continue
  add_watch_path "$(resolve_path_from_base "$class_path" "$hxml_dir")"
done < <(extract_class_paths)

# Useful defaults when iterating on this compiler repo and local examples.
add_watch_path "$root_dir/src"
add_watch_path "$root_dir/std"
add_watch_path "$root_dir/runtime"
add_watch_path "$root_dir/templates"
add_watch_path "$root_dir/haxe_libraries/reflaxe.rust.hxml"

for extra_path in "${extra_watch_paths[@]}"; do
  add_watch_path "$(resolve_path_from_base "$extra_path" "$invocation_dir")"
done

add_ignore_path "$root_dir/.git"
add_ignore_path "$root_dir/.cache"
add_ignore_path "$root_dir/target"
add_ignore_path "$root_dir/node_modules"
add_ignore_path "$rust_output_abs"

echo "[watch] mode=$mode debounce=${debounce_ms}ms hxml=$(display_path "$hxml_abs")"
echo "[watch] watch roots:"
for path in "${watch_paths[@]}"; do
  echo "  - $(display_path "$path")"
done
echo "[watch] ignored paths:"
for path in "${ignore_paths[@]}"; do
  echo "  - $(display_path "$path")"
done

watch_cmd=(bash "$script_path" --once --hxml "$hxml_abs" --mode "$mode" --haxe-bin "$haxe_bin" --cargo-bin "$cargo_bin")
watchexec_args=(-r -d "${debounce_ms}ms")

for path in "${watch_paths[@]}"; do
  watchexec_args+=(-w "$path")
done

for path in "${ignore_paths[@]}"; do
  watchexec_args+=(-i "$path")
done

watchexec_args+=(-- "${watch_cmd[@]}")
exec watchexec "${watchexec_args[@]}"
