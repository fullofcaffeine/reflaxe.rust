# Start Here (plain-language onboarding)

This guide is for teams that want native Rust binaries without becoming compiler experts.

Current status:

<!-- GENERATED:release-posture:start -->
Current release posture: **intentional `0.x` pre-1.0 posture**.

Maturity: **production-capable preview on validated lanes**. See [Semver And Release Posture](semver-release-posture.md).
<!-- GENERATED:release-posture:end -->

- the compiler/runtime baseline is closed and production-capable on validated lanes
- production use should still follow the proof-depth caveats in the [Production Readiness guide](production-readiness.md)

The shortest honest answer is: yes, use it for controlled production when your app stays inside the
validated surface and you add smoke tests for the system/runtime paths your app depends on.

If you are still orienting around the target's basic model, read the [FAQ](faq.md) for short answers
about garbage collection, memory management, generated Rust quality, runtime overhead, profile
choice, and Rust interop.

## What this compiler does

`reflaxe.rust` compiles Haxe 4.3.7 code into a Rust crate and runs Cargo by default.

In practice:

1. Write Haxe.
2. Emit Rust into `out/` (or configured output).
3. Build/run with Cargo.

## Two profile contracts

- `portable` (default): Haxe-portable semantics first.
- `metal`: Rust-first performance profile with strict typed boundaries.

Set profile with:

```bash
-D reflaxe_rust_profile=portable|metal
```

If you are unsure, start with `portable`. Move code to `metal` only when you have a concrete Rust
interop or performance reason.

## Fast path for first success

Use this path when you have a local checkout of this repo and want to prove the compiler works
before deciding anything architectural.

1. Install dependencies:

```bash
npm install
```

2. Build and run hello:

```bash
cd examples/hello
npx haxe compile.hxml
(cd out && cargo run -q)
```

3. Run CI-style local harness:

```bash
npm run test:all
```

If this is an application evaluation rather than compiler development, run the example first, then
scaffold a small project and add one smoke test for each external thing your app touches: files,
processes, sockets/HTTP, TLS, DB drivers, or threads.

The mental model is deliberately simple:

- `examples/hello` answers "does my toolchain work?"
- the generated starter answers "what should my app repo look like?"
- app-specific smoke tests answer "is my production surface covered?"

## Scaffold a new app

```bash
npm run dev:new-project -- ./my_haxe_rust_app
cd my_haxe_rust_app
cargo hx --action run
```

Generated projects include:

- `cargo hx` task driver (`run/test/build/release` flows),
- watch helper (`scripts/dev/watch-haxe-rust.sh`),
- compile task hxmls (`compile.hxml`, `compile.metal.hxml`, CI/release variants).

Recommended first generated-app loop:

```bash
cargo hx --action run
cargo hx --action test
cargo hx --action build --release
```

Read [Workflow](workflow.md#new-project-scaffold--task-hxmls) when you want the exact generated
task files and their Cargo behavior.

## Recommended profile choice

- Choose `portable` for default application development.
- Choose `metal` for hot paths, Rust-first APIs, and stricter performance intent.
- Keep raw Rust escape hatches behind typed wrappers; app code should not need direct `__rust__`.

Portable does not automatically mean "wrapper-heavy" on Rust. For abstractions whose semantics
line up cleanly, the compiler can still lower to the native Rust representation. Example:

- `reflaxe.std.Option<T>` -> Rust `Option<T>`
- `reflaxe.std.Result<T, E>` -> Rust `Result<T, E>`

Those examples describe admitted shared-package surfaces. The Rust backend has fixture coverage and
lowering for them, but this haxelib does not currently bundle the canonical `reflaxe.std` module
definitions; a consuming project must get those modules from the shared package once it exists, or
from an explicit local dependency during experiments.

`reflaxe.std` is intended to grow into a broader portable idiom layer over time. v1 starts with
`Option` / `Result` because those are small enough to lock semantics and migration rules first.

That native representation win is still part of the `portable` contract. The backend can optimize
portable lowering without silently changing the source-level contract to `metal` or native-lane
Rust APIs. Read [Portable near-native guidance](portable-near-native-guidance.md) for the
practical rule of thumb on when portable is already enough and when `metal` is the right move.

For Rust-first teams, the `metal` direction is haxified Rust: Rust-native authority through Haxe
constructs, typed metadata/macros, constrained DSLs, and extern facades where needed. Read
[Metal haxified Rust roadmap](metal-haxified-rust-roadmap.md) when evaluating that longer-term
compiler/API plan.

## Production evaluation checklist

Before adopting in a production service/tool:

1. Confirm your APIs are covered in the [feature support matrix](feature-support-matrix.md).
2. Run the generated app through `cargo hx --action test` or an equivalent CI command.
3. Add smoke tests for platform-sensitive behavior: process exit/error paths, network failures,
   TLS setup, DB driver setup, and thread/event-loop behavior if used.
4. Keep `portable` as the default profile and document every `metal` use as an intentional boundary.
5. Pin the toolchain and use locked Cargo builds in CI.

## Compare profiles in one example

```bash
cd examples/chat_loopback
npx haxe compile.hxml && (cd out && cargo run -q)
npx haxe compile.metal.hxml && (cd out_metal && cargo run -q)
```

Or with cargo driver:

```bash
cargo hx --project examples/chat_loopback --profile portable --action run
cargo hx --project examples/chat_loopback --profile metal --action run
```

## Quick metal parity check against native Rust

```bash
bash examples/profile_storyboard/scripts/compare-native.sh
```

This compares generated `metal` output with a hand-written Rust baseline for the same scenario and fails on drift.

## Read next

Install / workflow:

- [Install via lix](install-via-lix.md)
- [Workflow](workflow.md)

Portable-first:

- [Profiles](profiles.md)
- [Portable near-native guidance](portable-near-native-guidance.md)
- [Examples matrix](examples-matrix.md)

Metal-first:

- [Metal profile](metal-profile.md): current user-facing contract and boundary policy
- [Metal haxified Rust roadmap](metal-haxified-rust-roadmap.md): compiler/API improvement plan
- [Examples matrix](examples-matrix.md)
- [Profile migration guide](rusty-profile.md)

Release / operations:

- [Production Readiness](production-readiness.md)
- [Feature support matrix](feature-support-matrix.md)
- [Semantic confidence summary](semantic-confidence-summary.md)
- [Semver and release posture](semver-release-posture.md)
- [Defines reference](defines-reference.md)
- [Async contract](async-contract.md)
- [Async/Await guide](async-await.md)

Historical closeout context:

- [GA decision record](ga-decision-record.md)
- [GA caveat classification](ga-caveat-classification.md)
