# hello

Minimal portable sanity check for `reflaxe.rust`.

## Why

Use this example first when you want to prove the local Haxe -> Rust -> Cargo toolchain works before
looking at profiles, runtime APIs, or larger examples.

## What It Shows

- portable profile compilation,
- generated Cargo project output in `out/`,
- the smallest Haxe `main()` round-trip through generated Rust.

It intentionally does not show `metal`, native Rust interop, stdlib coverage, or production system
behavior. Those are covered by the larger examples in [Examples Matrix](../../docs/examples-matrix.md).

## Run

```bash
cd examples/hello
npx haxe compile.hxml
(cd out && cargo run -q)
```

Expected output:

```text
hi
```

## Watch Loop

From the repository root:

```bash
npm run dev:watch -- --hxml examples/hello/compile.hxml
```

## Read Next

- [Start Here](../../docs/start-here.md)
- [Workflow](../../docs/workflow.md)
- [Profiles](../../docs/profiles.md)
- [Examples Matrix](../../docs/examples-matrix.md)
