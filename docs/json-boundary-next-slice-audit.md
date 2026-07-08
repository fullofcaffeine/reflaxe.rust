# JSON Boundary Next Slice Audit

Status: `haxe.rust-oo3.97` audit.

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
   - The generated Rust currently calls those helpers by value, so read-only kind/accessor checks
     clone the same `Dynamic` repeatedly while walking objects and arrays.
   - This is a concrete output-shape cost that can be fixture-gated before any runtime behavior
     changes.

The best next implementation slice is therefore the typed `parseValue` boundary, not the already
optimized plain parse/stringify path.

## How

Follow-up work should happen in this order:

1. Add a JSON schema/typed-validation benchmark contract.
   - Extend the consumer-runtime benchmark corpus with a concrete fixture that exercises
     `haxe.Json.parseValue` plus typed validation over object/array/string/number fields.
   - Keep the existing round-trip JSON benchmark as the headline dynamic-boundary signal.
   - Use the same deterministic artifact flow as the current HXRT perf harness.
2. Add a contract-first output-shape fixture for borrowed introspection.
   - The expected generated Rust should borrow the inspected `Dynamic` for read-only
     `value_kind` / `value_as_*` / object-key / length checks.
   - Child extraction can still return owned `Dynamic` values where the typed `Value` tree needs
     ownership.
3. Change the native JSON introspection surface only after the fixtures fail for the current shape.
   - `std/hxrt/json/NativeJson.hx` can model read-only parameters as `rust.Ref<JsonValue>`.
   - `runtime/hxrt/src/json.rs` can accept `&Dynamic` for read-only kind/accessor helpers.
   - The implementation must preserve the semantic fixtures named in
     [JSON boundary contract](json-boundary-contract.md).

Non-goals for this slice:

- changing parsed dynamic object representation,
- changing replacer traversal semantics,
- replacing portable `HxString` with profile-specific native strings,
- adding a generic last-use clone-elision pass without JSON-boundary proof.
