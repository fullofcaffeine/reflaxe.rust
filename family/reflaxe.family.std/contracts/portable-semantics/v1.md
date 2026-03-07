# Portable Semantics Spec v1

Spec ID: `portable-semantics-v1`  
Status: Active  
Baseline: Haxe `4.3.7` portable-eligible stdlib surface  
Canonical implementation target: `reflaxe.rust` (`portable` contract)

This document defines the normative portable semantics contract for `reflaxe.rust`.

## Scope

This spec applies when code stays on portable-contract surfaces:

- Haxe language + portable-eligible stdlib/application code
- no `rust.*` imports in portable-contract modules
- no raw target injection in portable-contract modules

Portable surface membership is governed by `test/portable_allowlist.json`.

## Normative rules

### 1) Null and string behavior

1. `Std.string(null)` must produce `"null"`.
2. String concatenation with `null` must preserve portable `"null"` semantics.

Conformance fixtures:

- `test/semantic_diff/null_string_concat`

### 2) Exception flow and typed catches

1. `throw` / `try` / `catch` must preserve typed + dynamic catch behavior seen in `--interp`.
2. Catch ordering must match Haxe semantics.

Conformance fixtures:

- `test/semantic_diff/exceptions_typed_dynamic`

### 3) Virtual dispatch semantics

1. Base-typed values must dispatch overridden methods from derived implementations.
2. Calls from base methods into overridable methods must preserve dynamic dispatch behavior.

Conformance fixtures:

- `test/semantic_diff/virtual_dispatch`

### 4) Sys environment semantics

1. `Sys.getEnv(missingKey)` must return `null`.

Conformance fixtures:

- `test/semantic_diff/sys_getenv_null`

### 5) Portable Option/Result idiom semantics

1. Portable Option/Result constructor semantics (`Some`/`None`, `Ok`/`Err`) must remain stable.
2. Portable combinator-style flows (`map`, `andThen`, `mapErr`, `orElse`, `unwrapOr`) must preserve
   reference behavior from `--interp` outputs.

Conformance fixtures:

- `test/semantic_diff/portable_option_result_basics`

## Contract invariance across lanes

If code stays on portable surfaces, semantics must remain equivalent with and without portable metal lanes (`@:haxeMetal`/`@:rustMetal`) for lane-clean modules.

Conformance fixtures:

- `test/semantic_diff_lanes/lane_clean_arithmetic`
- `test/semantic_diff_lanes/lane_clean_dispatch`

## Conformance gates

Portable semantics changes are valid only when these remain green:

```bash
python3 test/run-semantic-diff.py
python3 test/run-semantic-diff.py --suite lanes
bash test/run-snapshots.sh
```
