#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$project_root"

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/dev/cargo-hx.sh [options]

Options:
  --profile <name>          Optional. Prefer compile.<profile>.hxml variants when present.
  --ci                      Prefer compile*.ci.hxml variants when present.
  --action <name>           Cargo action: build|run|test|check|clippy. Default: run.
  --release                 Run cargo action with --release and pass -D rust_release to Haxe.
  --haxe-bin <path>         Haxe binary. Default: $HAXE_BIN or haxe.
  --cargo-bin <path>        Cargo binary. Default: $CARGO_BIN or cargo.
  --quiet                   Add -q to cargo action (default).
  --no-quiet                Do not add -q.
  -h, --help                Show this help.

Examples:
  cargo hx --action run
  cargo hx --action test --ci
  cargo hx --action build --release
USAGE
}

fail() {
  echo "error: $*" >&2
  exit 2
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

profile=""
action="run"
ci=0
release=0
haxe_bin="${HAXE_BIN:-haxe}"
cargo_bin="${CARGO_BIN:-cargo}"
cargo_quiet=1

while [[ $# -gt 0 ]]; do
  case "$1" in
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

case "$action" in
  build|run|test|check|clippy) ;;
  *) fail "invalid --action '$action' (expected: build, run, test, check, or clippy)" ;;
esac

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
  if [[ -f "$project_root/$candidate" ]]; then
    selected_hxml="$candidate"
    break
  fi
done

if [[ -z "$selected_hxml" ]]; then
  available="$(cd "$project_root" && ls compile*.hxml 2>/dev/null | tr '\n' ' ' || true)"
  fail "no matching hxml (tried: ${candidates[*]}). Available: ${available:-<none>}"
fi

rust_output_rel="$(extract_rust_output "$project_root/$selected_hxml" || true)"
[[ -n "$rust_output_rel" ]] || fail "missing '-D rust_output=...' in $selected_hxml"
rust_output_abs="$project_root/$rust_output_rel"

echo "[hx-cargo] hxml=$selected_hxml out=$rust_output_rel action=$action release=$release ci=$ci profile=${profile:-auto}"

declare -a haxe_args=("$selected_hxml" "-D" "rust_no_build")
if [[ "$release" -eq 1 ]]; then
  haxe_args+=("-D" "rust_release")
fi

(cd "$project_root" && "$haxe_bin" "${haxe_args[@]}")

if [[ ! -f "$rust_output_abs/Cargo.toml" ]]; then
  fail "Cargo.toml not found after Haxe compile: $rust_output_rel"
fi

declare -a cargo_args=("$action")
if [[ "$cargo_quiet" -eq 1 ]]; then
  cargo_args+=("-q")
fi
if [[ "$release" -eq 1 ]]; then
  cargo_args+=("--release")
fi

echo "[hx-cargo] cargo ${cargo_args[*]} ($rust_output_rel)"
(cd "$rust_output_abs" && "$cargo_bin" "${cargo_args[@]}")

