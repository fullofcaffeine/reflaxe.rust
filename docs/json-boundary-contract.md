# JSON Boundary Contract

## Why

Post-`1.0`, JSON is the only current performance hotspot that is justified by the committed
evidence rather than by intuition.

That makes JSON boundary work unusually risk-sensitive:

- it is easy to make the benchmark graph happier by quietly weakening semantics,
- it is easy to optimize one path (`metal`) while accidentally blurring the portable contract,
- and it is easy to forget that `haxe.Json` is not just parse/stringify throughput, but also a
  typed/dynamic boundary used by reflection, exception payloads, and stdlib-facing code.

This document locks the optimization contract for the current narrow JSON hotspot work.

## What

The JSON hotspot covers two different obligations:

1. performance attribution
   - where the current cost actually comes from
2. semantic safety
   - what behavior must remain stable while that cost is reduced

### Current attribution

The current benchmark case is `test/perf/json/Main.hx`.

It exercises this path repeatedly:

1. build a Haxe anonymous payload
2. `haxe.Json.stringify(payload)`
3. `haxe.Json.parse(encoded)` into a runtime dynamic payload
4. `haxe.Json.stringify(decoded)` again

That means the measured cost is not “serde_json is slow”. It is mostly boundary work:

1. generated lowering builds the input payload in Haxe/Rust runtime shapes
2. `hxrt::json` walks those runtime shapes during stringify and writes JSON bytes directly
3. `hxrt::json` parses JSON straight into runtime `Dynamic` / `DynObject` / `Array<Dynamic>` shapes
4. replacer and reflection-facing paths add additional normalization/walking when used

The important post-fix nuance is that the old double-tree path is no longer the main explanation.
`hxrt::json` no longer needs to rebuild a full intermediate `serde_json::Value` tree for the plain
parse/stringify fast path, and the first post-`1.0` runtime-side optimization pass also removed the
extra key/value-buffer cloning on plain `DynObject` / `Anon` stringify walks.

The remaining gap is now mostly the cost of walking dynamic/runtime shapes themselves, plus the
portable-only string representation churn that still exists where the compiler cannot safely lower
to cheaper Rust display shapes.

### Current semantic contract

The following coverage is the minimum contract that future JSON optimization work must preserve:

- `test/semantic_diff/json_stringify_replacer`
  - root key `""`
  - object-field keys
  - array-index keys
  - replacer-before-descent traversal
- `test/semantic_diff/reflect_dynamic_receivers`
  - parsed JSON objects remain usable through `Reflect.hasField`, `Reflect.field`, and `Reflect.setField`
- `test/semantic_diff/exception_dynamic_payload`
  - dynamic payloads moving through exception paths remain reflectable and unboxed correctly
- `test/snapshot/json_parse_value_boundary`
  - `haxe.Json.parseValue` stays a typed `haxe.json.Value` boundary
  - pretty stringify remains stable on parsed/mutated dynamic objects

### Optimization targets that are allowed

- reduce avoidable allocations/clones inside `runtime/hxrt/src/json.rs`
- reduce avoidable generated-lowering overhead around JSON boundary values
- add backend-local fast paths that preserve the source-level portable contract

### Optimization moves that are not allowed

- changing `portable` semantics just to match a cheaper Rust representation
- removing reflection compatibility from parsed JSON dynamic objects
- changing replacer traversal order/keys
- treating `reflaxe.std` or backend-local facades as an excuse to blur `haxe.Json` contract behavior

## How

Use this contract in order:

1. keep or expand the semantic fixtures above
2. make attribution explicit in milestone notes / perf docs / commit messages
3. only then change runtime or lowering code
4. validate with:
   - targeted semantic diff cases
   - relevant snapshots if codegen/runtime copies drift
   - the perf harness / committed baseline flow

If a future optimization requires changing any behavior described here, it must first update this
contract document and the linked tests deliberately.
