# Consumer Runtime Benchmark Corpus

This corpus is the intake contract for runtime/tool-shaped performance pressure.

Use it when a consumer says "portable is too slow here" or "this needs metal" and the next step is
to turn that pressure into a generic `reflaxe.rust` fixture instead of a project-specific shortcut.

## Why this exists

The compiler should improve generic lowering, runtime helpers, and metal gates from representative
evidence. It should not learn one downstream application's layout, naming, or local environment.

This page defines the product-neutral benchmark candidates that can justify portable/metal work:

- DTO/codecs,
- JSON/schema validation,
- process/tool boundary shims,
- state transitions,
- async/runtime surfaces.

Each candidate states the expected source contract lane:

- `portable-first`: start from ordinary Haxe semantics and optimize lowering/runtime only when that
  preserves the contract.
- `metal-first`: the source model is intentionally Rust-native and should use typed native surfaces.
- `no-runtime lower-bound`: a constrained `metal + rust_no_hxrt` signal that shows the best possible
  generated Rust shape when Haxe runtime semantics are excluded.

## Admission Rules

A benchmark candidate can become an actual fixture only when it follows these rules:

1. Use generic names and data. Do not include downstream product names, paths, schemas, prompts,
   user workflows, or deployment assumptions.
2. Prefer typed Haxe models: typedefs, enums, enum abstracts, abstracts/newtypes, and explicit
   decoders. Keep `Dynamic` only at real JSON/thread/message/std boundaries, then convert back to
   typed values immediately.
3. Compile at least the relevant `portable` and `metal` profiles unless the candidate is explicitly
   a no-runtime lower-bound fixture.
4. Reuse the HXRT overhead artifact policy unless the candidate needs a documented extension:
   `current.json`, `comparison.json`, `summary.md`, repeatable sample counts, warning gates, and
   `pr` / `nightly` hard-gate modes.
5. If a candidate adds a new hard threshold, add an explicit `HXRT_PERF_*` override and document why
   the existing family thresholds are not enough.
6. Keep output-shape checks separate from noisy runtime measurements. For deterministic metal
   idiom properties such as unexpected `hxrt`, `Dynamic`, raw `ERaw`, clone noise, or slice
   materialization, use metal policy fixtures rather than timing alone.

## Threshold Reuse

The default policy is to reuse the existing
[HXRT overhead benchmark](perf-hxrt-overhead.md) gates.

| Candidate shape | Default threshold family | Notes |
| --- | --- | --- |
| Tight typed computation, state transitions, DTO transforms | `hot_loop_inproc` | Primary steady-state portable/metal and pure-Rust parity signal. |
| Byte/string codec loops | `bytes` | Use for buffer mutation/access, encode/decode, and zero-copy pressure. |
| JSON parse/validate/stringify | `json` | Use for dynamic boundary and schema validation work; keep future work tied to the JSON contract. |
| Haxe array/reference semantics | `array` | Use when Haxe array reference behavior is part of the measured surface. |
| Portable `haxe.Int64` semantics | `int64` | Warning-only portability-cost tracker, not a near-native KPI. |
| Runtime-free metal subset | `hot_loop_no_hxrt` | Lower-bound signal for `metal + rust_no_hxrt`. |
| Process/thread/async/example spread | `chat` style profile spread until stabilized | Warning-only unless an in-process, low-noise harness is added. |

Current warning convergence caps remain family-specific:

- `hot_loop_inproc`: portable/metal `<= 1.05x`
- `bytes`: portable/metal `<= 1.08x`
- `json`: portable/metal `<= 1.12x`
- `array`: portable/metal `<= 1.08x`
- `int64`: portable/metal `<= 1.08x`, warning-only

PR/nightly hard caps and size/runtime regression thresholds stay owned by
`docs/perf-hxrt-overhead.md` and the perf script. This corpus does not create a new hidden gate
policy.

## Candidate Matrix

| Area | Candidate fixture | Lane | Fixture status | Measurement policy | What it proves |
| --- | --- | --- | --- | --- | --- |
| DTO/codecs | `dto_codec_roundtrip` | `portable-first` | Proposed `test/perf/dto_codec` | Reuse `hot_loop_inproc` for typed transforms; reuse `bytes` when encode/decode is buffer-heavy. | Typed records/enums can round-trip without `Dynamic` or clone-heavy generated Rust. |
| DTO/codecs | `dto_result_option_surface` | `portable-first` | Existing shape: `test/snapshot/portable_facade_native_option_result`; proposed perf variant only if runtime pressure appears. | Output-shape gate first; perf only if there is measured runtime pressure. | Portable `reflaxe.std.Option/Result` keeps native Rust representation expectations. |
| JSON/schema validation | `json_schema_validate` | `portable-first` | Proposed extension of `test/perf/json` | Reuse `json` thresholds and artifact flow. | Parse dynamic JSON at the boundary, validate into typed structures, and stringify/report without avoidable runtime-shape churn. |
| JSON/schema validation | `json_error_report_codec` | `portable-first` | Proposed `test/perf/json_error_report` if needed. | Reuse `json`; compare portable/metal plus pure Rust baseline when the schema is stable. | Error-heavy validation paths do not force broad optimizer work or project-specific report shortcuts. |
| Process/tool boundary shims | `process_command_shim` | `metal-first` when strict host behavior is the source contract; otherwise `portable-first` through `sys.*`. | Proposed `test/perf/process_shim` or snapshot-only policy fixture. | Warning-only profile spread until a stable in-process harness exists. Output-shape gates may reject `Dynamic`/raw escape hatches. | Argument/env/exit-code shims stay typed and do not require app-side raw Rust. |
| Process/tool boundary shims | `tool_message_codec` | `portable-first` | Proposed `test/perf/tool_message_codec`. | Reuse `bytes` for binary framing or `json` for JSON framing. | Tool protocols should become generic codecs, not downstream-specific compiler knowledge. |
| State transitions | `typed_state_machine` | `portable-first` | Proposed `test/perf/state_machine`. | Reuse `hot_loop_inproc`. | Pure typed state updates should stay close across portable/metal when no runtime semantics are observed. |
| State transitions | `owned_state_snapshot` | `portable-first` | Proposed `test/perf/state_snapshot` if clone pressure appears. | Reuse `hot_loop_inproc`; add output-shape counters only for deterministic clone regressions. | Snapshot/update flows expose avoidable clone/allocation regressions without tying to a real app state model. |
| Async/runtime surfaces | `async_retry_pipeline` | `metal-first` for Rust async APIs; `portable-first` only when using portable runtime semantics. | Existing example family: `examples/async_retry_pipeline`; proposed perf fixture only after a stable timing harness exists. | Warning-only profile spread until timing noise is controlled. | Async task composition should be measured as a runtime surface, not inferred from sync microbenches. |
| Async/runtime surfaces | `thread_message_bridge` | `portable-first` when using Haxe thread semantics. | Existing snapshot families include thread/event-loop coverage; proposed perf fixture only if queue overhead becomes active pressure. | Warning-only unless an in-process low-noise harness exists. | Thread crossing and message payload boundaries stay typed after unavoidable runtime message boundaries. |
| Async/runtime surfaces | `scoped_lock_guard` | `metal-first` | Existing policy evidence: scoped RAII guard fixtures. | Output-shape and borrow-region gates first; runtime perf only if lock overhead becomes active pressure. | RAII-style guards use scoped callbacks or extern islands instead of fake storable lifetime tokens. |
| No-runtime lower bound | `no_hxrt_typed_hot_loop` | `no-runtime lower-bound` | Existing shape: `test/perf/hot_loop_no_hxrt`. | Reuse `hot_loop_no_hxrt`. | The constrained metal path remains a lower-bound signal for generated Rust without `hxrt`. |
| No-runtime lower bound | `no_hxrt_codec_kernel` | `no-runtime lower-bound` | Proposed only after DTO/codec fixture exists. | Reuse `bytes` plus `rust_no_hxrt` compatibility checks. | A typed codec kernel can prove how close the backend gets when runtime semantics are intentionally absent. |

## How To Use This Corpus

When a new performance or output-quality concern appears:

1. Map it to the closest candidate above.
2. If no candidate fits, add a new generic candidate before adding code.
3. Decide whether the source contract is `portable-first`, `metal-first`, or `no-runtime lower-bound`.
4. Reuse the threshold family in this page.
5. Add or update the fixture with generic names and data.
6. Record the fixture and gate in the owning docs:
   - performance thresholds: `docs/perf-hxrt-overhead.md`
   - source-style guidance: `docs/portable-vs-metal-authoring.md`
   - metal output shape gates: `docs/metal-haxified-rust-roadmap.md`
   - public first-user posture: `README.md` and `docs/faq.md` when behavior/status changes.

If the concern is only "this downstream app is slower than expected," the next action is a small
generic fixture from this corpus, not a downstream-named compiler branch.
