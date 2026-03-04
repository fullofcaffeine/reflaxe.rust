#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
cd "$ROOT_DIR"

use_rg=0
if [[ "${REFLAXE_NO_RG:-0}" != "1" ]] && command -v rg >/dev/null 2>&1; then
  use_rg=1
fi

scan_files() {
  git ls-files \
    | grep -Ev '^(vendor/|\.beads/|test/snapshot/.*/intended/|test/snapshot/.*/intended_metal/)' \
    | grep -E '\.(hx|cross\.hx|hxml|md|sh|json)$' || true
}

contains_line() {
  local needle="$1"
  shift
  local line
  for line in "$@"; do
    if [[ "$line" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

check_rule() {
  local rule_name="$1"
  local pattern="$2"
  shift 2
  local allowlist=("$@")
  local violations=0
  local hit

  while IFS= read -r hit || [ -n "$hit" ]; do
    [ -z "$hit" ] && continue
    local path="${hit%%:*}"
    if ! contains_line "$path" "${allowlist[@]}"; then
      if [ "$violations" -eq 0 ]; then
        echo "[guard:deprecated-defines] ERROR: ${rule_name} detected outside allowlisted files:" >&2
      fi
      echo "[guard:deprecated-defines] $hit" >&2
      violations=$((violations + 1))
    fi
  done < <(
    if [[ "$use_rg" -eq 1 ]]; then
      scan_files | while IFS= read -r file || [ -n "$file" ]; do
        [ -z "$file" ] && continue
        rg -n --with-filename --no-heading --color never "$pattern" "$file" || true
      done
    else
      scan_files | while IFS= read -r file || [ -n "$file" ]; do
        [ -z "$file" ] && continue
        grep -En "$pattern" "$file" | sed "s#^#${file}:#" || true
      done
    fi
  )

  if [ "$violations" -ne 0 ]; then
    return 1
  fi
  return 0
}

fail=0

removed_profile_allowlist=(
  "AGENTS.md"
  "docs/rusty-profile.md"
  "scripts/ci/check-metal-policy.sh"
  "test/negative/profile_removed_idiomatic/compile.hxml"
  "test/negative/profile_removed_rusty/compile.hxml"
)
if ! check_rule "removed profile selectors (idiomatic/rusty)" 'reflaxe_rust_profile=(idiomatic|rusty)' "${removed_profile_allowlist[@]}"; then
  fail=1
fi

removed_async_allowlist=(
  "CHANGELOG.md"
  "AGENTS.md"
  "docs/async-await.md"
  "docs/defines-reference.md"
  "scripts/lint/deprecated_define_guard.sh"
  "scripts/ci/check-metal-policy.sh"
  "src/reflaxe/rust/CompilerInit.hx"
  "test/negative/async_preview_removed/compile.hxml"
)
if ! check_rule "removed async define (rust_async_preview)" '(^|[^[:alnum:]_])rust_async_preview([^[:alnum:]_]|$)' "${removed_async_allowlist[@]}"; then
  fail=1
fi

removed_report_allowlist=(
  "AGENTS.md"
  "docs/profiles.md"
  "scripts/lint/deprecated_define_guard.sh"
)
if ! check_rule "removed report define names (rust_profile_contract_report/rust_hxrt_plan_report)" '(^|[^[:alnum:]_])(rust_profile_contract_report|rust_hxrt_plan_report)([^[:alnum:]_]|$)' "${removed_report_allowlist[@]}"; then
  fail=1
fi

if ! check_rule "removed report artifact names (profile_contract.*/hxrt_plan.*)" '(^|[^[:alnum:]_])(profile_contract\\.(json|md)|hxrt_plan\\.(json|md)|profile_contract\\.\\*|hxrt_plan\\.\\*)([^[:alnum:]_]|$)' "${removed_report_allowlist[@]}"; then
  fail=1
fi

stale_case_hits="$(git ls-files | grep -E '(^|/)test/snapshot/(idiomatic_profile|async_preview_retry)(/|$)' || true)"
if [[ -n "$stale_case_hits" ]]; then
  echo "[guard:deprecated-defines] ERROR: stale snapshot case names detected (rename to current portable/metal naming):" >&2
  echo "$stale_case_hits" | sed 's/^/[guard:deprecated-defines] /' >&2
  fail=1
fi

stale_report_hits="$(git ls-files | grep -E '(^|/)(profile_contract\\.(json|md)|hxrt_plan\\.(json|md))$' || true)"
if [[ -n "$stale_report_hits" ]]; then
  echo "[guard:deprecated-defines] ERROR: stale report artifact names detected (rename to contract_report.* / runtime_plan.*):" >&2
  echo "$stale_report_hits" | sed 's/^/[guard:deprecated-defines] /' >&2
  fail=1
fi

if [[ "$fail" -ne 0 ]]; then
  echo "[guard:deprecated-defines] Fix deprecated define drift or update this guard allowlist only when the exception is intentional and documented." >&2
  exit 1
fi

echo "[guard:deprecated-defines] OK"
