#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
invocation_dir="$(pwd)"
cd "$root_dir"

usage() {
  cat <<'USAGE'
Usage:
  cargo hx [run|build|test|check|clippy] [options]
  cargo hx dev [options]

Commands:
  run                       Compile Haxe and run the generated Rust app (default).
  build|test|check|clippy   Compile Haxe and run that Cargo command.
  dev                       Watch project inputs, recompile, and run on each change.

Options:
  --project <path>          Optional. Project directory containing compile*.hxml.
                            Default: current working directory.
  --profile <name>          Optional. Profile suffix (portable/metal).
  --hxml <path>             Optional. Explicit hxml file (relative to --project by default).
  --ci                      Prefer compile*.ci.hxml variants.
  --action <name>           Compatibility spelling for a one-shot command or dev.
  --mode <run|build|test>   Action repeated by `cargo hx dev`. Default: run.
  --watch <path>            Extra dev watch root, relative to the project (repeatable).
  --debounce-ms <n>         Dev rebuild delay. Default: 250.
  --once                    Run one dev cycle and exit.
  --no-haxe-server          Disable the incremental Haxe server in dev mode.
  --release                 Run cargo action with --release and pass -D rust_release to Haxe.
  --haxe-bin <path>         Haxe binary. Default: $HAXE_BIN or haxe.
  --cargo-bin <path>        Cargo binary. Default: $CARGO_BIN or cargo.
  --quiet                   Add -q to cargo action (default).
  --no-quiet                Do not add -q.
  -h, --help                Show this help.

Examples:
  cargo hx dev
  cargo hx dev --profile portable --mode test
  cargo hx run
  cargo hx test --ci
  cargo hx build --release
USAGE
}

fail() {
  echo "error: $*" >&2
  exit 2
}

display_path() {
  local input="$1"
  if [[ "$input" == "$invocation_dir" ]]; then
    printf ".\n"
  elif [[ "$input" == "$invocation_dir/"* ]]; then
    printf ".%s\n" "${input#"$invocation_dir"}"
  elif [[ "$input" == "$root_dir" ]]; then
    printf ".\n"
  elif [[ "$input" == "$root_dir/"* ]]; then
    printf "%s\n" "${input#"$root_dir/"}"
  else
    printf "[external:%s]\n" "$(basename "$input")"
  fi
}

normalize_existing_dir() {
  local input="$1"
  if [[ ! -d "$input" ]]; then
    fail "project directory not found: $(display_path "$input")"
  fi
  (cd "$input" && pwd)
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
  local hxml_path="$1"
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
  ' "$hxml_path"
}

project_arg="$invocation_dir"
profile=""
hxml_arg=""
action="run"
action_was_set=0
dev_mode="run"
dev_mode_was_set=0
dev_once=0
dev_no_haxe_server=0
dev_debounce_ms="250"
dev_debounce_was_set=0
declare -a dev_watch_paths=()
ci=0
release=0
haxe_bin="${HAXE_BIN:-haxe}"
cargo_bin="${CARGO_BIN:-cargo}"
cargo_quiet=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      [[ $# -ge 2 ]] || fail "--project requires a value"
      project_arg="$2"
      shift 2
      ;;
    --profile)
      [[ $# -ge 2 ]] || fail "--profile requires a value"
      profile="$2"
      shift 2
      ;;
    --hxml)
      [[ $# -ge 2 ]] || fail "--hxml requires a value"
      hxml_arg="$2"
      shift 2
      ;;
    --action)
      [[ $# -ge 2 ]] || fail "--action requires a value"
      [[ "$action_was_set" -eq 0 ]] || fail "choose either a positional command or --action, not both"
      action="$2"
      action_was_set=1
      shift 2
      ;;
    --mode)
      [[ $# -ge 2 ]] || fail "--mode requires a value"
      dev_mode="$2"
      dev_mode_was_set=1
      shift 2
      ;;
    --watch)
      [[ $# -ge 2 ]] || fail "--watch requires a value"
      dev_watch_paths+=("$2")
      shift 2
      ;;
    --debounce-ms)
      [[ $# -ge 2 ]] || fail "--debounce-ms requires a value"
      dev_debounce_ms="$2"
      dev_debounce_was_set=1
      shift 2
      ;;
    --once)
      dev_once=1
      shift
      ;;
    --no-haxe-server)
      dev_no_haxe_server=1
      shift
      ;;
    --ci)
      ci=1
      shift
      ;;
    --release)
      release=1
      shift
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
    --quiet)
      cargo_quiet=1
      shift
      ;;
    --no-quiet)
      cargo_quiet=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    run|build|test|check|clippy|dev)
      [[ "$action_was_set" -eq 0 ]] || fail "choose either a positional command or --action, not both"
      action="$1"
      action_was_set=1
      shift
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

case "$action" in
  build|run|test|check|clippy|dev) ;;
  *) fail "invalid command '$action' (expected: dev, build, run, test, check, or clippy)" ;;
esac

case "$dev_mode" in
  run|build|test) ;;
  *) fail "invalid --mode '$dev_mode' (expected: run, build, or test)" ;;
esac

if [[ "$action" != "dev" && ( "$dev_mode_was_set" -eq 1 || "$dev_once" -eq 1 || "$dev_no_haxe_server" -eq 1 || "$dev_debounce_was_set" -eq 1 || "${#dev_watch_paths[@]}" -gt 0 ) ]]; then
  fail "--mode, --watch, --debounce-ms, --once, and --no-haxe-server require the dev command"
fi

if [[ "$action" == "dev" && "$release" -eq 1 ]]; then
  fail "dev mode is an incremental debug loop; use 'cargo hx build --release' for a release build"
fi

project_abs="$(resolve_path_from_base "$project_arg" "$invocation_dir")"
project_dir="$(normalize_existing_dir "$project_abs")"

if [[ -n "$hxml_arg" && ( -n "$profile" || "$ci" -eq 1 ) ]]; then
  fail "--hxml cannot be combined with --profile/--ci"
fi

selected_hxml_arg=""
selected_hxml_abs=""

if [[ -n "$hxml_arg" ]]; then
  selected_hxml_abs="$(resolve_path_from_base "$hxml_arg" "$project_dir")"
  [[ -f "$selected_hxml_abs" ]] || fail "hxml not found: $(display_path "$selected_hxml_abs")"
  if [[ "$selected_hxml_abs" == "$project_dir/"* ]]; then
    selected_hxml_arg="${selected_hxml_abs#"$project_dir/"}"
  else
    selected_hxml_arg="$selected_hxml_abs"
  fi
else
  declare -a candidates=()
  if [[ "$ci" -eq 1 ]]; then
    if [[ -n "$profile" ]]; then
      candidates+=("compile.${profile}.ci.hxml")
    fi
    candidates+=("compile.ci.hxml")
    if [[ -n "$profile" ]]; then
      candidates+=("compile.${profile}.hxml")
    fi
    candidates+=("compile.hxml")
  else
    if [[ -n "$profile" ]]; then
      candidates+=("compile.${profile}.hxml")
    fi
    candidates+=("compile.hxml")
  fi

  for candidate in "${candidates[@]}"; do
    if [[ -f "$project_dir/$candidate" ]]; then
      selected_hxml_arg="$candidate"
      selected_hxml_abs="$project_dir/$candidate"
      break
    fi
  done

  if [[ -z "$selected_hxml_arg" ]]; then
    available="$(cd "$project_dir" && ls compile*.hxml 2>/dev/null | tr '\n' ' ' || true)"
    fail "no matching hxml in $(display_path "$project_dir") (tried: ${candidates[*]}). Available: ${available:-<none>}"
  fi
fi

rust_output_rel="$(extract_rust_output "$selected_hxml_abs" || true)"
[[ -n "$rust_output_rel" ]] || fail "missing '-D rust_output=...' in $(display_path "$selected_hxml_abs")"
rust_output_abs="$(resolve_path_from_base "$rust_output_rel" "$project_dir")"

echo "[hx-cargo] project=$(display_path "$project_dir") profile=${profile:-auto} ci=$ci action=$action release=$release"
echo "[hx-cargo] hxml=$selected_hxml_arg out=$(display_path "$rust_output_abs")"

if [[ "$action" == "dev" ]]; then
  watcher_script="$root_dir/scripts/dev/watch-haxe-rust.sh"
  [[ -f "$watcher_script" ]] || fail "watcher script not found: scripts/dev/watch-haxe-rust.sh"

  declare -a watcher_args=(
    --hxml "$selected_hxml_abs"
    --mode "$dev_mode"
    --debounce-ms "$dev_debounce_ms"
    --haxe-bin "$haxe_bin"
    --cargo-bin "$cargo_bin"
  )
  if [[ "$dev_once" -eq 1 ]]; then
    watcher_args+=(--once)
  fi
  if [[ "$dev_no_haxe_server" -eq 1 ]]; then
    watcher_args+=(--no-haxe-server)
  fi
  for watch_path in "${dev_watch_paths[@]:-}"; do
    watcher_args+=(--watch "$(resolve_path_from_base "$watch_path" "$project_dir")")
  done

  echo "[hx-cargo] dev mode=$dev_mode haxe_server=$([[ "$dev_no_haxe_server" -eq 1 ]] && printf off || printf auto)"
  exec bash "$watcher_script" "${watcher_args[@]}"
fi

declare -a haxe_args=("$selected_hxml_arg" "-D" "rust_no_build")
if [[ "$release" -eq 1 ]]; then
  haxe_args+=("-D" "rust_release")
fi

(cd "$project_dir" && "$haxe_bin" "${haxe_args[@]}")

if [[ ! -f "$rust_output_abs/Cargo.toml" ]]; then
  fail "Cargo.toml not found after Haxe compile: $(display_path "$rust_output_abs")"
fi

declare -a cargo_args=("$action")
if [[ "$cargo_quiet" -eq 1 ]]; then
  cargo_args+=("-q")
fi
if [[ "$release" -eq 1 ]]; then
  cargo_args+=("--release")
fi

echo "[hx-cargo] cargo ${cargo_args[*]} ($(display_path "$rust_output_abs"))"
(cd "$rust_output_abs" && "$cargo_bin" "${cargo_args[@]}")
