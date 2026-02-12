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

## Full harness and artifact cleanup

Run the full local CI harness (snapshots + upstream stdlib sweep + examples):

```sh
npm run test:all
```

By default, `test:all` removes generated `out*` folders and `.cache/*target*` at the end of the run to control disk growth.

- Keep artifacts for debugging:

```sh
npm run test:all:keep
```

- Manual cleanup commands:

```sh
npm run clean:artifacts
npm run clean:artifacts:all
```

## Update intended outputs

Only do this after you’ve inspected the generated Rust and you’re confident it’s the correct output.

```sh
test/run-snapshots.sh --case class_fields_methods --update
```
