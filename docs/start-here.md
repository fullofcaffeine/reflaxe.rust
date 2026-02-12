# Start Here (for non-compiler users)

This guide is for people who want to build Rust apps with Haxe, but are not compiler experts.
It explains the practical path to success first, then points to deeper technical docs when needed.

## What `reflaxe.rust` is

`reflaxe.rust` is a Haxe target that compiles Haxe 4.3.7 code into a Rust crate, then builds a native binary via Cargo by default.

In plain terms:

- You write Haxe.
- The compiler generates Rust in `out/`.
- Cargo builds your app as a native executable.

## Choose your profile

The project currently supports **three** profiles (not two):

1. `portable` (default): best for cross-target Haxe code and teams that do not want to think about Rust details.
2. `idiomatic`: same semantics as portable, but cleaner Rust output (fewer warnings/noise).
3. `rusty`: Rust-first APIs (`rust.*`) for teams that want more direct control over ownership/borrowing surfaces.

Set profile with:

```bash
-D reflaxe_rust_profile=portable|idiomatic|rusty
```

Compatibility alias:

```bash
-D rust_idiomatic
```

## Fast path: first native app

1. Install dependencies:

```bash
npm install
```

2. Build and run a sample:

```bash
cd examples/hello
../node_modules/.bin/haxe compile.hxml
(cd out && cargo run -q)
```

3. Run project tests:

```bash
npm run test:all
```

## What “production ready” means here

For this project, 1.0 means:

- full sys-target stdlib parity for Haxe 4.3.7 (with documented exceptions),
- stable compiler/runtime behavior across profiles,
- CI + local harness coverage for compiler output and example apps,
- clear docs for both Haxe-first and Rust-first users.

Track live status in `docs/progress-tracker.md`.

## Interop ladder (recommended order)

Use the highest-level option that solves your problem:

1. Pure Haxe + std overrides/runtime APIs.
2. Typed externs (`@:native`) and metadata (`@:rustCargo`, `@:rustExtraSrc`).
3. Framework-level wrappers around native Rust modules.
4. Raw `__rust__` escape hatch (last resort, not app-level default).

Policy for apps/examples:

- avoid direct `__rust__` calls in app code,
- keep injections behind typed APIs in framework/runtime layers.

## Read next

- `docs/progress-tracker.md` (current readiness to 1.0)
- `docs/vision-vs-implementation.md` (what matches the original vision, what still gaps)
- `docs/profiles.md` (portable/idiomatic/rusty model)
- `docs/workflow.md` (build knobs and Cargo controls)
- `docs/rusty-profile.md` (Rust-first authoring style)
- `docs/v1.md` (technical support matrix)
