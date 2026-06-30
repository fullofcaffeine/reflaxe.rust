# FAQ

This FAQ is for two audiences at once:

- Rust-native readers asking what kind of Rust `reflaxe.rust` emits and how much runtime machinery
  is involved.
- Haxe-native readers asking which Haxe semantics carry over when Rust is the target.

For the full contract model, read [Profiles](profiles.md). For adoption posture, read
[Production Readiness](production-readiness.md).

## Is there garbage collection support?

There is no always-on tracing garbage collector in the normal generated Rust output.

`reflaxe.rust` preserves Haxe reference semantics with Rust-owned values and a small runtime crate
(`hxrt`) where Haxe semantics require one. Today, ordinary Haxe reference values are represented
with runtime handles such as `HxRef<T>`, which use Rust shared ownership and interior mutability
rather than a tracing GC.

That means:

- Rust still drops owned values when their owners go away.
- Shared Haxe-style references are reference-counted by Rust primitives.
- Strong reference cycles are not automatically collected like they would be by a tracing GC. If
  your application builds long-lived cyclic object graphs, design an explicit break/cleanup point or
  use a more Rust-shaped data model.
- `hxrt` is not a VM-level garbage collector. It is a Rust runtime support crate for Haxe semantics
  such as reference values, arrays, nullable strings, dynamic values, exceptions, selected std/sys
  APIs, and async/threading glue where enabled.

From the Haxe side, you usually do not manually free memory. From the Rust side, the model should be
read as Rust ownership plus explicit runtime handles where portable Haxe behavior needs them.

## How does memory management work?

The short version:

- Pure value-like data should lower to ordinary Rust-owned values where the active contract permits
  it.
- Haxe class instances and other Haxe reference values use runtime reference handles so assignment,
  aliasing, nullability, mutation, and thread crossing can follow Haxe expectations.
- `portable` keeps Haxe semantics first, even when that needs `hxrt`.
- `metal` is the opt-in Rust-first contract for native handles, scoped borrows, RAII-style guards,
  stricter boundaries, and reduced/no-runtime experiments.

Concrete examples:

- `Int`, `Bool`, `Float`, and many enum/value paths lower toward normal Rust scalar/value shapes.
- `reflaxe.std.Option<T>` and `reflaxe.std.Result<T, E>` lower to Rust `Option<T>` and
  `Result<T, E>` on this backend.
- `Array<T>` currently maps to a lightweight runtime array over a shared `Vec<T>` handle because
  Haxe arrays are nullable, assignable reference values with mutation semantics.
- Portable nullable strings use the runtime string representation. Metal defaults to non-null Rust
  `String` semantics unless you ask for nullable strings.

The design goal is not "wrap everything because it came from Haxe." The goal is to use native Rust
representations whenever Haxe-observable behavior permits it, and to keep any remaining runtime cost
visible, measured, and justified.

## Is the generated Rust meant to look like hand-written Rust?

Yes. Generated Rust quality is a product requirement, not a cosmetic nicety.

The target should emit readable, `rustfmt`-friendly, warning-clean Rust with native representations,
predictable ownership, and minimal avoidable cloning/allocation. When good Haxe source still emits
poor Rust, that is treated as a generic compiler/runtime improvement opportunity rather than a reason
to write awkward Haxe or hide Codex/app-specific hacks in the backend.

The project tracks this with snapshot tests, generated output review, `rustfmt`, warning controls,
performance/HXRT overhead benchmarks, and profile contract reports.

## What are `portable` and `metal`?

`portable` is the default Haxe-semantics-first contract. Use it for normal application code,
migration paths, and code that should stay Haxe-shaped.

`metal` is the Rust-semantics-first contract. Use it for hot paths, Rust-native APIs, typed native
boundaries, explicit ownership/borrow-shaped code, and reduced/no-runtime work.

`idiomatic` is not a profile selector. It is the output-quality bar for both contracts:

- idiomatic portable output when Haxe semantics are preserved;
- idiomatic metal output when Rust-first semantics are intentionally selected.

Read [Portable near-native guidance](portable-near-native-guidance.md) when deciding whether a hot
path can stay portable or should move to metal.

## Should I start with `portable` or `metal`?

Start with `portable` unless you already know the source contract must be Rust-first.

Move a module or boundary to `metal` when you have a concrete reason:

- the source should use Rust-native APIs;
- a native handle, borrow, or RAII guard is the real model;
- an app boundary should reject dynamic/reflection-heavy behavior;
- a measured hotspot still needs a Rust-first contract after portable lowering is already clean.

Do not choose `metal` as a vague "make it fast" switch. The backend should make portable output fast
when it can prove Haxe semantics are preserved.

## How much runtime overhead should I expect?

It depends on the semantics your program uses.

Code that stays in scalar/value-like, typed, non-dynamic paths can get close to ordinary Rust
lowering. Code that uses Haxe reference semantics, nullable strings, `Dynamic`, reflection-like
operations, exceptions, arrays, threads, async helpers, or std/sys APIs may use `hxrt`.

The project treats runtime overhead as a measured budget. See
[HXRT overhead benchmarks](perf-hxrt-overhead.md) for the current benchmark protocol and
[Portable near-native guidance](portable-near-native-guidance.md) for the optimization posture.

## Can I build without `hxrt`?

Sometimes, in `metal`.

`-D rust_no_hxrt` is a metal-only minimal-runtime mode. It omits the bundled `hxrt` dependency and
fails if generated output still needs runtime support. This is useful for constrained Rust-first
islands, but it is not the default Haxe compatibility path.

See [Defines Reference](defines-reference.md#contracts-and-semantics).

## Does the Haxe stdlib lower to efficient Rust?

That is the goal wherever semantics allow it.

The target should prefer direct, idiomatic Rust lowering for stdlib operations when a native Rust
primitive has the same behavior. When Haxe semantics require runtime help, the runtime layer should
be as thin and optimized as practical. If an stdlib path pays unnecessary wrapper/runtime tax, that
should become a backend/runtime optimization issue, not a permanent source-level workaround.

Current support and proof depth are tracked in the [Feature support matrix](feature-support-matrix.md)
and [Stdlib Parity Policy](stdlib-policy.md).

## Can Haxe code use low-level Rust primitives?

Yes, intentionally.

The `rust.*` API surface exposes Rust-shaped concepts such as references, mutable references,
borrows, vectors, maps, slices, `Option`, and `Result`. These are best used at typed native
boundaries, in `metal`, or in clearly marked Rust-first modules.

Prefer typed APIs and helpers over raw Rust injection. Raw `untyped __rust__(...)` remains an escape
hatch for narrow low-level abstraction modules, but app code should normally use typed externs,
metadata, or framework facades.

See [Interop](interop.md), [Metal profile](metal-profile.md), and
[Lifetime encoding design](lifetime-encoding.md).

## Can I use Rust crates from Haxe?

Yes. The preferred path is typed interop:

1. Define a typed Haxe extern/facade.
2. Add Cargo dependencies with metadata or generated project configuration.
3. Keep crate-specific details behind a small boundary module.
4. Use raw Rust only inside the boundary if the typed facilities cannot express the operation yet.

This keeps Haxe application code reviewable and keeps generated Rust close to normal Rust module
ownership.

## Does Haxe `Dynamic` work?

Portable supports intentional dynamic boundaries, but `Dynamic` is not free and should not be used as
a default data model for Rust-facing code.

From a Rust-native perspective, dynamic values usually imply runtime boxing, downcasts, field lookup
helpers, and weaker static guarantees. From a Haxe perspective, use `Dynamic` at real dynamic
boundaries, then decode into typed structures as soon as practical.

`metal` is deliberately stricter around reflection/runtime-introspection and dynamic map semantics.

See [Dynamic boundaries](dynamic-boundaries.md).

## How does `null` work?

Haxe nullability is preserved where the active contract says it must be.

In portable, strings default to a nullable runtime representation so Haxe string null behavior is
available. In metal, `String` defaults to non-null Rust `String` semantics; use `Null<String>` when a
nullable value is the real contract.

For Rust-native optional values, prefer typed option shapes such as `reflaxe.std.Option<T>` or
`rust.Option<T>` depending on the layer you are writing.

See [Null option](null-option.md).

## Does async/concurrency work?

There is a supported Rust-first async subset, but it is not a blanket promise that every Haxe async
or threading pattern maps to every runtime mode.

Use the documented async contract and add app-specific tests around task cancellation, joining,
thread crossing, IO, and shutdown paths. For Rust-native readers, the current model is explicit
runtime adapter support rather than hidden async magic.

See [Async contract](async-contract.md), [Async/Await guide](async-await.md), and
[Concurrency posture](concurrency-posture.md).

## Is this production ready?

Use it for controlled production on validated lanes, with app-specific smoke tests for the runtime
paths your application actually touches.

Do not read "production-ready" as "every possible Haxe/std/sys edge is proven on every host." The
support matrix, semantic-confidence evidence, and your own app tests define the real production
surface.

See [Production Readiness](production-readiness.md), [Feature support matrix](feature-support-matrix.md),
and [Semantic confidence summary](semantic-confidence-summary.md).

## Can I edit the generated Rust?

No. Treat generated Rust as build output.

If the generated Rust is wrong, inefficient, unreadable, or missing a capability, fix the Haxe source,
the compiler, or the runtime. Manual edits to generated Rust will be overwritten and hide the actual
backend issue.

## What should a first user read next?

- Haxe-first path: [Start Here](start-here.md), [Profiles](profiles.md), and
  [Examples matrix](examples-matrix.md).
- Rust-first path: [Metal profile](metal-profile.md), [Portable vs metal authoring](portable-vs-metal-authoring.md),
  and [Interop](interop.md).
- Production evaluation: [Production Readiness](production-readiness.md), [Feature support matrix](feature-support-matrix.md),
  and [HXRT overhead benchmarks](perf-hxrt-overhead.md).
