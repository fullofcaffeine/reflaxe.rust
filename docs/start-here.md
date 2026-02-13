# Start Here (plain-language onboarding)

This guide is for teams that want native Rust binaries without becoming compiler experts.

## What this compiler does

`reflaxe.rust` compiles Haxe 4.3.7 code into a Rust crate and then runs Cargo by default.

In practice:

1. You write Haxe.
2. The target emits Rust into `out/`.
3. Cargo builds a native executable.

## Two usage styles, three profiles

Most users think in two styles:

- Portable-first: keep code mostly cross-target Haxe.
- Rust-first: write Haxe with explicit Rust concepts.

Implementation detail: the compiler provides three profiles:

- `portable` (default): safest default, best for Haxe-first teams.
- `idiomatic`: same semantics as portable, cleaner Rust output.
- `rusty`: Rust-first APIs and borrow-oriented surface.

Set profile with:

```bash
-D reflaxe_rust_profile=portable|idiomatic|rusty
```

Alias:

```bash
-D rust_idiomatic
```

## Fast path for first success

1. Install dependencies:

```bash
npm install
```

2. Build and run the hello example:

```bash
cd examples/hello
../node_modules/.bin/haxe compile.hxml
(cd out && cargo run -q)
```

3. Run the CI-style local harness:

```bash
npm run test:all
```

## Recommended profile choice

- Pick `portable` if your team is mostly Haxe-first.
- Pick `idiomatic` if you want cleaner generated Rust but no behavior shift.
- Pick `rusty` if your team wants tighter control over Rust-like ownership/interop surfaces.

## Interop ladder (use highest-level option first)

1. Pure Haxe + standard library/runtime APIs.
2. Typed externs + metadata (`@:native`, `@:rustCargo`, `@:rustExtraSrc`).
3. Framework wrappers around hand-written Rust modules.
4. Raw `__rust__` escape hatch only when necessary.

Policy target for production apps:

- app code stays pure Haxe,
- low-level Rust stays behind typed boundaries.

## What "production-ready 1.0" means in this repo

- The release gate epic `haxe.rust-4jb` is closed.
- Sys-target stdlib parity scope is met and tested.
- CI harness (`npm run test:all`) is green.
- Docs match real compiler/runtime behavior.

Track status here:

- `docs/progress-tracker.md`

## Read next

- `docs/production-readiness.md`
- `docs/road-to-1.0.md`
- `docs/profiles.md`
- `docs/defines-reference.md`
- `docs/vision-vs-implementation.md`
- `docs/workflow.md`
