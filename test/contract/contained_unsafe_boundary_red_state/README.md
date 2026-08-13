# Contained unsafe support-crate red state

This fixture records why haxe.rust needs a new typed support-crate boundary.
It does not implement that boundary.

`compile.hxml` copies `native/unsafe_probe.rs` into the generated application
crate with `@:rustExtraSrc`. The application keeps `#![forbid(unsafe_code)]`,
so Cargo must reject the helper's one unsafe block.

`compile.ambient-path.hxml` links `support/` as a separate Cargo crate with
`@:rustCargo({path: ...})`. Cargo accepts the separate unsafe implementation,
but generated `Cargo.toml` points to `../support`. haxe.rust does not copy,
validate, hash, or package the support source.

Run the complete contract from the repository root:

```sh
npm run test:support-crate-boundary
```

The test verifies both outcomes and removes its generated output.
