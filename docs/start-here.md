# Start Here (plain-language onboarding)

This guide is for teams that want native Rust binaries without becoming compiler experts.

Current status:

- the compiler/runtime baseline is closed and production-capable on validated lanes
- stable `1.x` public posture is recorded in the [Semver and release posture decision](semver-release-posture.md)

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

## Fast path for first success

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

## Recommended profile choice

- Choose `portable` for default application development.
- Choose `metal` for hot paths, Rust-first APIs, and stricter performance intent.

Portable does not automatically mean "wrapper-heavy" on Rust. For abstractions whose semantics
line up cleanly, the compiler can still lower to the native Rust representation. Example:

- `reflaxe.std.Option<T>` -> Rust `Option<T>`
- `reflaxe.std.Result<T, E>` -> Rust `Result<T, E>`

That keeps the portable authoring surface while aiming for Rust-native cost on this backend.

`reflaxe.std` is intended to grow into a broader portable idiom layer over time. v1 starts with
`Option` / `Result` because those are small enough to lock semantics and migration rules first.

That native representation win is still part of the `portable` contract. The backend can optimize
portable lowering without silently changing the source-level contract to `metal` or native-lane
Rust APIs. Read [Portable near-native guidance](portable-near-native-guidance.md) for the
practical rule of thumb on when portable is already enough and when `metal` is the right move.

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

Portable-first:

- [Profiles](profiles.md)
- [Portable near-native guidance](portable-near-native-guidance.md)
- [Examples matrix](examples-matrix.md)

Metal-first:

- [Metal profile](metal-profile.md)
- [Examples matrix](examples-matrix.md)
- [Profile migration guide](rusty-profile.md)

Release / operations:

- [Production Readiness](production-readiness.md)
- [Semver and release posture](semver-release-posture.md)
- [Defines reference](defines-reference.md)
- [Async contract](async-contract.md)
- [Async/Await guide](async-await.md)

Historical closeout context:

- [GA decision record](ga-decision-record.md)
- [GA caveat classification](ga-caveat-classification.md)
