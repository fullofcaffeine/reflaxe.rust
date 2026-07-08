# JSON Boundary Next Slice Audit

Status: `haxe.rust-oo3.97` audit, with `haxe.rust-oo3.97.1` benchmark coverage and
`haxe.rust-oo3.97.2` borrowed-introspection lowering landed.

## Why

The current JSON perf signal is useful only if follow-up work stays attached to observed boundary
costs. The plain `haxe.Json.parse` / `haxe.Json.stringify` path already avoids the old
double-`serde_json::Value` tree and writes/parses directly against runtime `Dynamic` shapes.

That leaves a narrower question for the next tranche: which JSON boundary cost is still visible,
covered by contract fixtures, and small enough to improve without weakening Haxe JSON semantics?

## What

The current evidence points to three distinct paths:

1. plain dynamic round trip
   - `test/perf/json/Main.hx` builds an anonymous payload, stringifies it, parses into `Dynamic`,
     then stringifies the parsed value again.
   - `runtime/hxrt/src/json.rs` now uses direct serde serializer/deserializer adapters for this
     path.
   - This remains the benchmark headline, but it is no longer the best first place to hunt for a
     broad runtime rewrite.
2. replacer traversal
   - `stringify` with a replacer still normalizes through runtime JSON values before applying the
     callback.
   - That path is semantics-heavy: root key `""`, object keys, array-index keys, and
     replacer-before-descent ordering are all part of the contract.
   - It should not be optimized until a replacer-specific benchmark or attribution fixture exists.
3. typed `parseValue` conversion
   - `std/haxe/Json.cross.hx` converts a parsed `Dynamic` into `haxe.json.Value` by calling native
     JSON introspection helpers.
   - This used to call read-only helpers by value, so kind/accessor checks cloned the same
     `Dynamic` repeatedly while walking objects and arrays.
   - `haxe.rust-oo3.97.2` now models those read-only helper parameters as borrowed
     `rust.Ref<JsonValue>` and gates the generated Rust shape with
     `test/snapshot/json_parse_value_boundary`.

The selected implementation slice was therefore the typed `parseValue` boundary, not the already
optimized plain parse/stringify path.

## How

Follow-up work should happen in this order:

1. Add a JSON schema/typed-validation benchmark contract.
   - `test/perf/json_schema_validate` exercises `haxe.Json.parseValue` plus typed validation over
     object/array/string/number/bool/null fields.
   - Keep the existing round-trip JSON benchmark as the headline dynamic-boundary signal.
   - Use the same deterministic artifact flow as the current HXRT perf harness.
2. Add a contract-first output-shape fixture for borrowed introspection. Done:
   - `test/snapshot/json_parse_value_boundary` now expects read-only
     `value_kind` / `value_as_*` / object-key / length checks to borrow the inspected
     `Dynamic` as `&value`.
   - Child extraction still returns owned `Dynamic` values where the typed `Value` tree needs
     ownership.
3. Change the native JSON introspection surface only after the fixtures fail for the old shape.
   Done:
   - `std/hxrt/json/NativeJson.hx` models read-only parameters as `rust.Ref<JsonValue>`.
   - `runtime/hxrt/src/json.rs` accepts `&Dynamic` for read-only kind/accessor helpers.
   - The semantic fixtures named in [JSON boundary contract](json-boundary-contract.md) remain the
     guardrails for future changes.

Non-goals for this slice:

- changing parsed dynamic object representation,
- changing replacer traversal semantics,
- replacing portable `HxString` with profile-specific native strings,
- adding a generic last-use clone-elision pass without JSON-boundary proof.
