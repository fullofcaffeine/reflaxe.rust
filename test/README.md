# Snapshot tests

Snapshot tests live under `test/snapshot/<case>/`:

- `Main.hx` (and any other `.hx` files) — the Haxe source for the case
- `compile.hxml` — build script (must include `-main <Class>`)
- `intended/` — committed “golden” Rust output
- `out/` — generated on each test run (ignored by git)

## Run all snapshots

```sh
test/run-snapshots.sh
```

This:
- recompiles each case with `haxe compile.hxml -D rust_no_build` (codegen-only; the harness builds via Cargo)
- checks `cargo fmt -- --check`
- checks `cargo build -q`
- diffs `intended/` vs `out/`

## Update intended outputs

Only do this after you’ve inspected the generated Rust and you’re confident it’s the correct output.

```sh
test/run-snapshots.sh --case class_fields_methods --update
```
