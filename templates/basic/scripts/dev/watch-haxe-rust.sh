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
  --no-haxe-server      Disable Haxe compile server in watch mode.
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

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
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
no_haxe_server=0
if is_truthy "${HAXE_RUST_WATCH_NO_SERVER:-0}"; then
  no_haxe_server=1
fi
haxe_server_port="${HAXE_RUST_WATCH_SERVER_PORT:-}"
haxe_server_owned=0
use_haxe_server=0
haxe_server_pid=""
haxe_server_log=""
declare -a haxe_compile_extra_args=()
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
    --no-haxe-server)
      no_haxe_server=1
      shift
      ;;
    --haxe-server-port)
      [[ $# -ge 2 ]] || fail "--haxe-server-port requires a value"
      haxe_server_port="$2"
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
if [[ "$no_haxe_server" -eq 1 && -n "$haxe_server_port" ]]; then
  fail "--no-haxe-server cannot be combined with --haxe-server-port"
fi
if [[ -n "$haxe_server_port" && ! "$haxe_server_port" =~ ^[0-9]+$ ]]; then
  fail "--haxe-server-port must be a non-negative integer"
fi
if [[ -n "$haxe_server_port" ]]; then
  use_haxe_server=1
fi
if [[ "$once" -eq 0 && "$no_haxe_server" -eq 0 ]]; then
  use_haxe_server=1
  haxe_server_owned=1
fi

haxe_compile_extra_args=()
case "$mode" in
  run|test)
    # In run/test watcher modes we execute Cargo ourselves after codegen.
    # Force Haxe compile to skip the backend's automatic cargo invocation.
    haxe_compile_extra_args+=("-D" "rust_no_build")
    ;;
  build)
    # Keep build mode deterministic: avoid accidental `cargo run/test` if the hxml
    # default task sets `rust_cargo_subcommand` to something other than `build`.
    haxe_compile_extra_args+=("-D" "rust_cargo_subcommand=build")
    ;;
esac

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

stop_haxe_server() {
  if [[ -n "$haxe_server_pid" ]]; then
    if kill -0 "$haxe_server_pid" >/dev/null 2>&1; then
      kill "$haxe_server_pid" >/dev/null 2>&1 || true
    fi
    wait "$haxe_server_pid" >/dev/null 2>&1 || true
    haxe_server_pid=""
  fi
}

cleanup() {
  stop_haxe_server
  if [[ -n "$haxe_server_log" && -f "$haxe_server_log" ]]; then
    rm -f "$haxe_server_log"
  fi
}

trap cleanup EXIT INT TERM

wait_for_haxe_server_ready() {
  local attempt
  for ((attempt = 1; attempt <= 40; attempt++)); do
    if "$haxe_bin" --connect "$haxe_server_port" -version >/dev/null 2>&1; then
      return 0
    fi
    if [[ -n "$haxe_server_pid" ]] && ! kill -0 "$haxe_server_pid" >/dev/null 2>&1; then
      return 1
    fi
    sleep 0.1
  done
  return 1
}

start_owned_haxe_server() {
  local max_attempts=12
  local forced_port=0
  if [[ -n "$haxe_server_port" ]]; then
    forced_port=1
    max_attempts=1
  fi

  haxe_server_log="$(mktemp "${TMPDIR:-/tmp}/haxe-rust-watch-server.XXXXXX.log")"

  local attempt
  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    local candidate_port
    if [[ "$forced_port" -eq 1 ]]; then
      candidate_port="$haxe_server_port"
    else
      candidate_port="$((20000 + RANDOM % 30000))"
    fi

    haxe_server_port="$candidate_port"
    "$haxe_bin" --wait "$haxe_server_port" >"$haxe_server_log" 2>&1 &
    haxe_server_pid="$!"

    if wait_for_haxe_server_ready; then
      echo "[watch] haxe compile server ready on port $haxe_server_port"
      return 0
    fi

    stop_haxe_server
  done

  echo "[watch] warning: unable to start haxe compile server; continuing without incremental cache." >&2
  if [[ -s "$haxe_server_log" ]]; then
    echo "[watch] haxe --wait log (last 10 lines):" >&2
    tail -n 10 "$haxe_server_log" >&2 || true
  fi

  use_haxe_server=0
  haxe_server_owned=0
  haxe_server_port=""
  return 1
}

run_haxe_compile_direct() {
  (cd "$hxml_dir" && "$haxe_bin" "$hxml_file" "${haxe_compile_extra_args[@]}")
}

run_haxe_compile_via_server() {
  [[ -n "$haxe_server_port" ]] || return 1
  (cd "$hxml_dir" && "$haxe_bin" --connect "$haxe_server_port" "$hxml_file" "${haxe_compile_extra_args[@]}")
}

run_haxe_compile() {
  if [[ "$use_haxe_server" -eq 1 ]]; then
    if run_haxe_compile_via_server; then
      return 0
    fi

    echo "[watch] warning: haxe --connect failed on port $haxe_server_port; retrying once." >&2
    if run_haxe_compile_via_server; then
      return 0
    fi

    echo "[watch] warning: falling back to direct haxe compile for this cycle." >&2
  fi

  run_haxe_compile_direct
}

run_cycle() {
  echo "[watch] compiling $(display_path "$hxml_abs")"
  run_haxe_compile

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
  for existing in "${watch_paths[@]:-}"; do
    if [[ "$existing" == "$target" ]]; then
      return 0
    fi
  done
  return 1
}

path_in_ignore_paths() {
  local target="$1"
  local existing
  for existing in "${ignore_paths[@]:-}"; do
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

for extra_path in "${extra_watch_paths[@]:-}"; do
  add_watch_path "$(resolve_path_from_base "$extra_path" "$invocation_dir")"
done

add_ignore_path "$root_dir/.git"
add_ignore_path "$root_dir/.cache"
add_ignore_path "$root_dir/target"
add_ignore_path "$root_dir/node_modules"
add_ignore_path "$rust_output_abs"

if [[ "$haxe_server_owned" -eq 1 ]]; then
  start_owned_haxe_server || true
fi

haxe_server_label="disabled"
if [[ "$use_haxe_server" -eq 1 && -n "$haxe_server_port" ]]; then
  haxe_server_label="enabled(port=$haxe_server_port)"
fi

echo "[watch] mode=$mode debounce=${debounce_ms}ms hxml=$(display_path "$hxml_abs") haxe_server=${haxe_server_label}"
echo "[watch] watch roots:"
for path in "${watch_paths[@]}"; do
  echo "  - $(display_path "$path")"
done
echo "[watch] ignored paths:"
for path in "${ignore_paths[@]}"; do
  echo "  - $(display_path "$path")"
done

watch_cmd=(bash "$script_path" --once --hxml "$hxml_abs" --mode "$mode" --haxe-bin "$haxe_bin" --cargo-bin "$cargo_bin")
if [[ "$use_haxe_server" -eq 1 && -n "$haxe_server_port" ]]; then
  watch_cmd+=(--haxe-server-port "$haxe_server_port")
fi
watchexec_args=(-r -d "${debounce_ms}ms")

for path in "${watch_paths[@]}"; do
  watchexec_args+=(-w "$path")
done

for path in "${ignore_paths[@]}"; do
  watchexec_args+=(-i "$path")
done

watchexec_args+=(-- "${watch_cmd[@]}")
watchexec "${watchexec_args[@]}"
