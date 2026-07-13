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
3. Throwing a concrete emitted instance and catching its base class or implemented interface must
   follow the Haxe subtype relation on the supported non-generic hierarchy slice.

Conformance fixtures:

- `test/semantic_diff/exceptions_typed_dynamic`
- `test/semantic_diff/typed_catch_interface`
- `test/semantic_diff/typed_catch_subclass`

### 3) Core dispatch and mutable-lvalue semantics

1. Base-typed values must dispatch overridden methods from derived implementations.
2. Calls from base methods into overridable methods must preserve dynamic dispatch behavior.
3. A concrete or multi-level generic superclass instantiation must specialize inherited storage,
   constructor behavior, method signatures, and base-typed dispatch without leaking free type
   parameters into generated Rust.
4. Generic interfaces inherited through a superclass chain must be implemented on the concrete
   child storage type with composed interface arguments; interface-parent specialization follows
   the same rule.
5. Concrete and base-typed field compound assignments must evaluate the receiver once, capture an
   owned current value before the RHS, end any read borrow before user code runs, and preserve Haxe
   expression-result semantics. Base-typed updates dispatch through the generated polymorphic field
   contract. Numeric prefix/postfix updates preserve new/old results through the same storage paths.
6. Mutable static field compound assignments and numeric prefix/postfix updates must use the
   generated static storage contract. Compound assignment captures the getter result before the RHS
   and preserves assigned-value semantics; prefix/postfix forms preserve new/old results.
7. Copy-like numeric array-element compound and prefix/postfix updates plus `Array<String>` append
   assignment must update through the typed array storage contract. Compound assignment resolves
   the array, index, and current element before the RHS, evaluates each source expression once, and
   preserves the assigned-value result; prefix/postfix forms preserve new/old results.
8. Non-empty array literals must evaluate each source element once in order and coerce it through
   the literal's unified element type before storage. Nullable primitive elements use `Some(value)`
   for non-null sources and `None` for null; reusable reference values preserve Haxe aliasing rather
   than being moved away from subsequent source uses.
9. Static accessor properties must dispatch through their typed getter/setter methods for ordinary,
   compound, prefix/postfix, and String updates, preserving accessor calls and setter results.
10. Copy-like anonymous-object field compound updates must capture the object and current typed value
   before the RHS, end the read borrow before user code runs, and write through the existing typed
   anonymous get/set contract.

Conformance fixtures:

- `test/semantic_diff/generic_base_specialization`
- `test/semantic_diff/generic_interface_specialization`
- `test/semantic_diff/array_index_updates`
- `test/semantic_diff/array_string_element_append`
- `test/semantic_diff/nullable_array_literals`
- `test/semantic_diff/field_compound_rhs_mutation`
- `test/semantic_diff/polymorphic_field_updates`
- `test/semantic_diff/static_field_updates`
- `test/semantic_diff/static_property_updates`
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

If code stays on portable surfaces, semantics must remain equivalent with and without portable metal lanes (`@:rustMetal`, with `@:haxeMetal` accepted as a compatibility alias) for lane-clean modules.

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
