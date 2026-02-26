# Start Here (plain-language onboarding)

This guide is for teams that want native Rust binaries without becoming compiler experts.

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

## Read next

- [Profiles](profiles.md)
- [Examples matrix](examples-matrix.md)
- [Metal profile](metal-profile.md)
- [Profile migration guide](rusty-profile.md)
- [Async/Await preview](async-await.md)
- [Defines reference](defines-reference.md)
