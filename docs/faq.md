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
- Uninitialized Haxe class fields keep Haxe's nullable-reference default: generated Rust stores a
  null `HxRef<T>` handle instead of eagerly calling nested class constructors.
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

Generic helper signatures are part of that output-quality contract. When a helper returns or accepts
a generated class payload such as `Payload<T>`, the compiler should propagate the payload's Rust
trait bounds into the helper signature at compile time instead of adding an `hxrt` workaround.

The project tracks this with snapshot tests, generated output review, `rustfmt`, warning controls,
performance/HXRT overhead benchmarks, profile contract reports, and a metal idiom count guard that
tracks selected clone/borrow/runtime-reference counters for curated output-shape fixtures.

## What are `portable` and `metal`?

`portable` is the default Haxe-semantics-first contract. Use it for normal application code,
migration paths, and code that should stay Haxe-shaped.

`metal` is the Rust-semantics-first contract. Use it for hot paths, Rust-native APIs, typed native
boundaries, explicit ownership/borrow-shaped code, and reduced/no-runtime work.

The long-term metal direction is haxified Rust: Rust-native authority expressed with Haxe
constructs, typed metadata/macros, constrained DSLs, and small extern facades where Rust's lifetime
or type-system surface is too rich to encode directly. See
[Metal haxified Rust roadmap](metal-haxified-rust-roadmap.md).

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

The compiler should still answer compile-time questions at compile time. Optional field metadata,
literal defaults, static access paths, and other typed-AST facts should be lowered into generated Rust
rather than moved behind runtime helper APIs.

That includes the narrow typed reflection subset. For example, `Reflect.compare` over typed `Int`,
`Float`, and `String` lowers to direct Rust comparison code instead of an `hxrt` helper.

The project treats runtime overhead as a measured budget. See
[HXRT overhead benchmarks](perf-hxrt-overhead.md) for the current benchmark protocol and
[Portable near-native guidance](portable-near-native-guidance.md) for the optimization posture.
When a runtime/tool-shaped consumer pressure appears, it should be reduced to one of the generic
fixtures in the [Consumer runtime benchmark corpus](consumer-runtime-benchmark-corpus.md) before it
becomes a compiler or runtime gate.

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

For example, `String.substring(start, end)` is lowered by the compiler to Haxe-compatible
clamp/swap bounds logic plus the existing string slicing helper; it should not generate a phantom
Rust `substring` method call.

Current support and proof depth are tracked in the [Feature support matrix](feature-support-matrix.md)
and [Stdlib Parity Policy](stdlib-policy.md).

## Can Haxe code use low-level Rust primitives?

Yes, intentionally.

The `rust.*` API surface exposes Rust-shaped concepts such as references, mutable references,
borrows, vectors, maps, slices, `Option`, `Result`, paths, and selected native/system concepts.
These are best used at typed native boundaries, in `metal`, or in clearly marked Rust-first modules.

For Haxe `Array<T>` values in metal code, `SliceTools.with(...)` and `MutSliceTools.with(...)` borrow
the underlying storage as scoped Rust slice views instead of cloning the array into a temporary
`Vec<T>`.

For systems APIs, keep the contract split in mind. Portable `sys.io.File` and `sys.io.Process`
preserve Haxe semantics and may use `hxrt` for handles, streams, exceptions, and platform behavior.
Rust-native metal code should use typed `rust.*` facades instead. Today that includes the first
`rust.fs.NativeFiles` file/path slice and the `rust.process.NativeCommands` owned-command slice.
`rust.process.CommandOutput` covers status/stdout/stderr from one owned run, and the process facade
now supports explicit command working directories, typed environment set/remove/clear operations, and
combined cwd+env plus one-shot stdin-input and stdin+cwd+env owned-command calls. Use
`rust.process.CommandSpec` when a command needs one typed owned config value for program/args plus
optional cwd, env, and stdin settings. Use the `Detailed` command/output methods with
`rust.process.CommandError` when recovery needs typed IO/stdin/UTF-8 error categories instead of
String-only diagnostics. Use `rust.process.CommandChild` only for the narrow no-hxrt lifecycle
case: spawn from a `CommandSpec`, write and close one stdin payload, wait, or kill and wait.
It is not a live `sys.io.Process` stream/shell/async replacement.
For networking, `rust.net.NativeTcp` is a narrow blocking localhost TCP proof with typed
`TcpListener` / `TcpStream` wrappers, and `rust.net.NativeUdp` is a narrow blocking localhost
datagram proof with a typed `UdpSocket` wrapper. The TCP facade supports UTF-8 streams and
byte streams as `rust.Vec<Int>` values; the UDP facade supports UTF-8 datagrams and byte datagrams
with the same typed byte representation. Send bytes are validated before converting to Rust `u8`.
Use socket `Detailed` methods with `rust.net.SocketError` when recovery needs typed invalid-input,
IO, or UTF-8 categories instead of String-only diagnostics. These are not portable
`sys.net.Socket` parity, TLS, async networking, live stream adapters, or arbitrary host/address
APIs yet.

Prefer typed APIs and helpers over raw Rust injection. Raw `untyped __rust__(...)` remains an escape
hatch for narrow low-level abstraction modules, but app code should normally use typed externs,
metadata, or framework facades.

See [Interop](interop.md), [Metal profile](metal-profile.md), and
[Lifetime encoding design](lifetime-encoding.md). For the broader compiler/API direction, see
[Metal haxified Rust roadmap](metal-haxified-rust-roadmap.md). For the current file/process/socket
handle plan, see [Metal systems facades roadmap](metal-systems-facades-roadmap.md).

## Can Haxe express Rust lifetimes?

Partially, through scoped borrow helpers rather than Rust lifetime syntax.

Haxe does not have native lifetime parameters, so `reflaxe.rust` models the useful first slice as
lexical borrow regions: `Borrow.withRef/withMut`, `SliceTools.with`, `MutSliceTools.with`, and
`StrTools.with`. The callback token is a borrow-only value and must not be returned, stored, assigned
outside the region, captured by a returned closure, or escaped through a local alias. Owned values
derived from the borrow are fine. Overlapping local-source mutable scopes such as nested
`Borrow.withMut(values, ...)` or `MutSliceTools.with(values, ...)` are rejected before Rust codegen;
sequential scoped mutable borrows of the same value are accepted.

Thread/task spawn boundaries also reject captured borrow-only values such as `rust.Ref<T>`,
`rust.MutRef<T>`, `rust.Slice<T>`, `rust.MutSlice<T>`, and `rust.Str` under the Send/Sync policy.
Wrapper/constructor/helper/object escapes and `throw` payloads are rejected when the escaped value
still contains a borrow-only type; more complex source-provenance checks remain compiler follow-up
work.

See [Lifetime encoding design](lifetime-encoding.md).

## How should I model Rust RAII guards?

Use scoped callbacks for simple lexical guards, and extern Rust islands for lifetime-heavy APIs.

`rust.concurrent.Mutexes.withRef/withMut` and `rust.concurrent.RwLocks.withRead/withWrite` keep the
real Rust guard inside HXRT and pass a scoped `rust.Ref<T>` / `rust.MutRef<T>` token to the callback.
Returning or storing that token is rejected by the borrow-region analyzer. File, socket, TLS,
transaction, parser, or `unsafe` guard APIs should usually use a small typed extern facade that
returns owned values.

See [RAII guard and lifetime-island rules](raii-guard-lifetime-islands.md).

## Can I use Rust crates from Haxe?

Yes. The preferred path is typed interop:

1. Define a typed Haxe extern/facade.
2. Add Cargo dependencies with metadata or generated project configuration.
3. Keep crate-specific details behind a small boundary module.
4. Use raw Rust only inside the boundary if the typed facilities cannot express the operation yet.

This keeps Haxe application code reviewable and keeps generated Rust close to normal Rust module
ownership.

For lifetime-heavy, HRTB, const-generic, macro-heavy, or `unsafe` Rust APIs, use the
[Extern and lifetime-island cookbook](extern-lifetime-island-cookbook.md) pattern: put the Rust-only
complexity in a tiny Rust module and expose a typed Haxe facade.

## Does Haxe `Dynamic` work?

Portable supports intentional dynamic boundaries, but `Dynamic` is not free and should not be used as
a default data model for Rust-facing code.

From a Rust-native perspective, dynamic values usually imply runtime boxing, downcasts, field lookup
helpers, and weaker static guarantees. From a Haxe perspective, use `Dynamic` at real dynamic
boundaries, then decode into typed structures as soon as practical.

`metal` is deliberately stricter around reflection/runtime-introspection and dynamic map semantics.

See [Dynamic boundaries](dynamic-boundaries.md).

## Do anonymous records work?

Portable supports typed anonymous structural records by lowering general record literals to a small
runtime object (`HxRef<hxrt::anon::Anon>`). Required fields are accessed through their declared Haxe
types, including `Int` fields returned from helpers or decoded from `haxe.json.Value` helpers.

Omitted `@:optional` fields also work: generated Rust checks whether the runtime anonymous object has
the key and returns the field type's Haxe null representation when it is absent.

## How does `null` work?

Haxe nullability is preserved where the active contract says it must be.

In portable, strings default to a nullable runtime representation so Haxe string null behavior is
available. In metal, `String` defaults to non-null Rust `String` semantics; use `Null<String>` when a
nullable value is the real contract.

For Rust-native optional values, prefer typed option shapes such as `reflaxe.std.Option<T>` or
`rust.Option<T>` depending on the layer you are writing.

Reference-like Haxe values such as classes already have explicit runtime null handles. Generic APIs
like `Array<Class>.shift()` may use `Option` internally, but typed `Null<Class>` callsites map the
empty case back to that null handle.

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
  [HXRT overhead benchmarks](perf-hxrt-overhead.md), and
  [Consumer runtime benchmark corpus](consumer-runtime-benchmark-corpus.md).
