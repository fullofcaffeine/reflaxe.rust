#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
invocation_dir="$(pwd)"
cd "$root_dir"

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/dev/cargo-hx.sh [options]

Options:
  --project <path>          Optional. Project directory containing compile*.hxml.
                            Default: current working directory.
  --profile <name>          Optional. Profile suffix (portable/idiomatic/rusty/metal).
  --hxml <path>             Optional. Explicit hxml file (relative to --project by default).
  --ci                      Prefer compile*.ci.hxml variants.
  --action <name>           Cargo action: build|run|test|check|clippy. Default: run.
  --release                 Run cargo action with --release and pass -D rust_release to Haxe.
  --haxe-bin <path>         Haxe binary. Default: $HAXE_BIN or haxe.
  --cargo-bin <path>        Cargo binary. Default: $CARGO_BIN or cargo.
  --quiet                   Add -q to cargo action (default).
  --no-quiet                Do not add -q.
  -h, --help                Show this help.

Examples:
  cd examples/chat_loopback && cargo hx --profile portable --action run
  cargo hx --project examples/chat_loopback --profile portable --ci --action test
  cargo hx --project ./my_haxe_rust_app --action build --release
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
      action="$2"
      shift 2
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
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

case "$action" in
  build|run|test|check|clippy) ;;
  *) fail "invalid --action '$action' (expected: build, run, test, check, or clippy)" ;;
esac

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
