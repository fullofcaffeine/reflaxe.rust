#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
invocation_dir="$(pwd)"
cd "$root_dir"

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/dev/cargo-hx.sh [--example <name>] [options]

Options:
  --example <name>          Optional. Folder name under examples/. If omitted and the
                            current working directory is inside examples/<name>/..., it
                            is inferred automatically.
  --profile <name>          Optional. Profile suffix (portable/idiomatic/rusty/metal).
  --ci                      Prefer compile*.ci.hxml variants.
  --action <name>           Cargo action: build|run|test|check|clippy. Default: run.
  --release                 Run cargo action with --release and pass -D rust_release to Haxe.
  --haxe-bin <path>         Haxe binary. Default: $HAXE_BIN or haxe.
  --cargo-bin <path>        Cargo binary. Default: $CARGO_BIN or cargo.
  --quiet                   Add -q to cargo action (default).
  --no-quiet                Do not add -q.
  -h, --help                Show this help.

Examples:
  cargo hx --example chat_loopback --profile portable --action run
  cd examples/chat_loopback && cargo hx --profile portable --action run
  cargo hx --example chat_loopback --profile portable --ci --action test
  cargo hx --example chat_loopback --profile metal --action build --release
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
  elif [[ "$input" == "$invocation_dir/"* ]]; then
    printf ".%s\n" "${input#"$invocation_dir"}"
  else
    printf "[external:%s]\n" "$(basename "$input")"
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

example_name=""
profile=""
action="run"
ci=0
release=0
haxe_bin="${HAXE_BIN:-haxe}"
cargo_bin="${CARGO_BIN:-cargo}"
cargo_quiet=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --example)
      [[ $# -ge 2 ]] || fail "--example requires a value"
      example_name="$2"
      shift 2
      ;;
    --profile)
      [[ $# -ge 2 ]] || fail "--profile requires a value"
      profile="$2"
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

if [[ -z "$example_name" ]]; then
  invocation_abs="$(cd "$invocation_dir" && pwd)"
  if [[ "$invocation_abs" == "$root_dir/examples/"* ]]; then
    rel="${invocation_abs#"$root_dir/examples/"}"
    example_name="${rel%%/*}"
  else
    fail "missing --example <name> (or run from examples/<name>/...)"
  fi
fi
case "$action" in
  build|run|test|check|clippy) ;;
  *) fail "invalid --action '$action' (expected: build, run, test, check, or clippy)" ;;
esac

example_dir="$root_dir/examples/$example_name"
[[ -d "$example_dir" ]] || fail "example not found: examples/$example_name"

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

selected_hxml=""
for candidate in "${candidates[@]}"; do
  if [[ -f "$example_dir/$candidate" ]]; then
    selected_hxml="$candidate"
    break
  fi
done

if [[ -z "$selected_hxml" ]]; then
  available="$(cd "$example_dir" && ls compile*.hxml 2>/dev/null | tr '\n' ' ' || true)"
  fail "no matching hxml for example '$example_name' (tried: ${candidates[*]}). Available: ${available:-<none>}"
fi

rust_output_rel="$(extract_rust_output "$example_dir/$selected_hxml" || true)"
[[ -n "$rust_output_rel" ]] || fail "missing '-D rust_output=...' in examples/$example_name/$selected_hxml"
rust_output_abs="$example_dir/$rust_output_rel"

echo "[hx-cargo] example=$example_name profile=${profile:-auto} ci=$ci action=$action release=$release"
echo "[hx-cargo] hxml=$(display_path "$example_dir/$selected_hxml") out=$(display_path "$rust_output_abs")"

declare -a haxe_args=("$selected_hxml" "-D" "rust_no_build")
if [[ "$release" -eq 1 ]]; then
  haxe_args+=("-D" "rust_release")
fi

(cd "$example_dir" && "$haxe_bin" "${haxe_args[@]}")

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
