# Start Here (plain-language onboarding)

This guide is for teams that want native Rust binaries without becoming compiler experts.

## What this compiler does

`reflaxe.rust` compiles Haxe 4.3.7 code into a Rust crate and then runs Cargo by default.

In practice:

1. You write Haxe.
2. The target emits Rust into `out/`.
3. Cargo builds a native executable.

## Two usage styles, four profiles

Most users think in two styles:

- Portable-first: keep code mostly cross-target Haxe.
- Rust-first: write Haxe with explicit Rust concepts.

Implementation detail: the compiler provides four profiles:

- `portable` (default): safest default, best for Haxe-first teams.
- `idiomatic`: same semantics as portable, cleaner Rust output.
- `rusty`: Rust-first APIs and borrow-oriented surface.
- `metal` (experimental): Rusty+ with typed low-level interop façade and stricter default app-boundary rules.

Set profile with:

```bash
-D reflaxe_rust_profile=portable|idiomatic|rusty|metal
```

Alias:

```bash
-D rust_idiomatic
-D rust_metal
```

## Fast path for first success

1. Install dependencies:

```bash
npm install
```

2. Build and run the hello example:

```bash
cd examples/hello
npx haxe compile.hxml
(cd out && cargo run -q)
```

3. Run the CI-style local harness:

```bash
npm run test:all
```

## Scaffold a new app

Use the built-in template generator:

```bash
npm run dev:new-project -- ./my_haxe_rust_app
cd my_haxe_rust_app
cargo hx --action run
```

The scaffold includes plumbing by default:

- `cargo hx ...` task driver (`run/test/build/release` flows).
- `scripts/dev/watch-haxe-rust.sh` for watch-mode compile+run/test loops.
- explicit `compile*.hxml` compatibility tasks.

## Faster local loop while you iterate

When you want instant feedback after each file save, use the watcher:

```bash
npm run dev:watch -- --hxml examples/hello/compile.hxml
```

Detailed watcher docs: [Dev Watcher](dev-watcher.md).

By default, watch mode keeps a Haxe compile server warm for faster incremental rebuilds.

## Recommended profile choice

- Pick `portable` if your team is mostly Haxe-first.
- Pick `idiomatic` if you want cleaner generated Rust but no behavior shift.
- Pick `rusty` if your team wants tighter control over Rust-like ownership/interop surfaces.
- Pick `metal` when `rusty` is not enough and you need typed low-level Rust snippets behind strict boundaries.

## Profile reference app (side-by-side)

Use `examples/chat_loopback` when you want to compare the same scenario across all profiles.

```bash
cd examples/chat_loopback
npx haxe compile.portable.hxml && (cd out_portable && cargo run -q)
npx haxe compile.idiomatic.hxml && (cd out_idiomatic && cargo run -q)
npx haxe compile.rusty.hxml && (cd out_rusty && cargo run -q)
npx haxe compile.metal.hxml && (cd out_metal && cargo run -q)
```

Cargo-flag workflow (same scenarios, less HXML-task sprawl):

```bash
cargo hx --project examples/chat_loopback --profile portable --action run
cargo hx --project examples/chat_loopback --profile idiomatic --action run
cargo hx --project examples/chat_loopback --profile rusty --action run
cargo hx --project examples/chat_loopback --profile metal --action run

# from inside examples/chat_loopback you can omit --project:
# cargo hx --profile portable --action run
```

Full scenario/profile map: [Examples matrix](examples-matrix.md).

## Interop ladder (use highest-level option first)

1. Pure Haxe + standard library/runtime APIs.
2. Typed externs + metadata (`@:native`, `@:rustCargo`, `@:rustExtraSrc`).
3. Framework wrappers around hand-written Rust modules.
4. Raw `__rust__` escape hatch only when necessary.

Policy target for production apps:

- app code stays pure Haxe,
- low-level Rust stays behind typed boundaries.

## What "production-ready 1.0" means in this repo

- The 1.0 release readiness gate is closed.
- Sys-target stdlib parity scope is met and tested.
- CI harness (`npm run test:all`) is green.
- Docs match real compiler/runtime behavior.

Track status here:

- [Progress Tracker](progress-tracker.md)

## Read next

- [Dev Watcher](dev-watcher.md)
- [Production Readiness](production-readiness.md)
- [Road to 1.0](road-to-1.0.md)
- [Profiles](profiles.md)
- [Examples matrix](examples-matrix.md)
- [Metal profile](metal-profile.md)
- [Lifetime encoding design](lifetime-encoding.md)
- [Async/Await preview](async-await.md)
- [Defines reference](defines-reference.md)
- [Vision vs Implementation](vision-vs-implementation.md)
- [Workflow](workflow.md)
