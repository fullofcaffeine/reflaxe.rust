# Rust Interop (No `__rust__` in apps)

This target supports an escape hatch (`__rust__`) for emitting raw Rust, but **v1.0 policy is:**

- Application code should stay “pure Haxe” (no raw `__rust__` calls).
- Rust interop belongs in **framework code** (`std/`, `runtime/`) behind typed APIs.

This doc describes the recommended, stable pattern for binding to Rust.

## Preferred pattern: `extern` + `@:native(...)` + extra Rust modules

### 1) Write the Rust module (hand-written)

Put a `.rs` file in a directory and include it via `-D rust_extra_src=...`:

- Haxe: `-D rust_extra_src=native` (directory relative to the `haxe` working directory)
- Rust file: `native/my_module.rs`

The compiler copies it into the generated crate and emits `mod my_module;` automatically.

### 2) Bind from Haxe with `extern` + `@:native(...)`

```haxe
@:native("crate::my_module")
extern class MyModule {
  @:native("some_fn")
  public static function someFn(x:Int): Int;
}
```

Notes:

- `@:native("crate::my_module")` maps the extern class to a Rust module path.
- `@:native("some_fn")` maps the Haxe field to the Rust function name.
- Keep the extern surface tiny and then wrap it with more idiomatic Haxe APIs if needed.

### 3) Test it with snapshots or cargo tests

- For small APIs, add a snapshot under `test/snapshot/*` that compiles + builds the generated crate.
- For richer behavior, add `native/*.rs` tests and run `cargo test` in CI (see `examples/tui_todo`).

## Cargo dependencies from Haxe

Prefer declarative dependencies:

- Put `@:rustCargo({ name: "crate_name", version: "x.y" })` metadata on the extern type that needs it.

This keeps Cargo wiring centralized and avoids ad-hoc `Cargo.toml` edits in app repos.

### `@:rustCargo` forms

Two forms are supported:

- Raw TOML line:
  - `@:rustCargo("ratatui = \"0.26\"")`
- Structured object (recommended; deterministic + mergeable):
  - `@:rustCargo({ name: "serde", version: "1", features: ["derive"] })`

### `@:rustCargo` object fields

Supported fields:

- `name` (required): crate name
- `version`: Cargo version requirement (e.g. `"1"`, `"0.26"`, `"^1.2"`)
- `features`: array of feature strings
- `defaultFeatures`: boolean (`false` to emit `default-features = false`)
- `optional`: boolean
- `path`: local path dependency
- `git`: git URL dependency
- `branch` / `tag` / `rev`: optional git selectors
- `package`: override the package name (Cargo’s `package = "..."` field)

If multiple modules declare `@:rustCargo` for the same crate:

- `features` are unioned + de-duped (stable order)
- most other fields must match (conflicts produce a compile-time error)

## Extra Rust trait impls (`@:rustImpl`)

Sometimes you want to implement a Rust trait for a **Haxe-emitted type** without dropping down to raw
`__rust__` in app code (for example `Display`, or a small marker trait).

Use `@:rustImpl(...)` metadata on the Haxe class/enum:

```haxe
@:rustImpl("std::marker::Unpin")
@:rustImpl("std::fmt::Display",
  "fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {\n" +
  "  write!(f, \"Foo({})\", self.x)\n" +
  "}")
class Foo {
  public var x:Int;
  public function new(x:Int) this.x = x;
}
```

Supported forms:

- `@:rustImpl("path::Trait")` emits an empty impl block: `impl path::Trait for Type { }`
- `@:rustImpl("path::Trait", "fn ...")` emits the provided string as the **inner body** of the impl block
- `@:rustImpl({ trait: "path::Trait", body: "fn ...", forType: "SomeType" })` (advanced)
  - `forType` overrides the Rust type name used on the right-hand side of `for ...`

Limitations:

- Rust orphan rules still apply. In practice, this is primarily useful for implementing external traits
  for **local types** (types emitted by this compiler). If both the trait and the target type are
  external, Rust will reject the impl.

## Escape hatch: `__rust__` injection (framework-only)

If a binding is awkward to express as an extern (generics/closures, tricky lifetimes, etc.), you can
use `__rust__` **inside framework code** as a last resort.

Two ways exist:

- `untyped __rust__("...{0}...", arg0)` — works in normal (non-macro) modules
- `reflaxe.rust.macros.RustInjection.__rust__("...{0}...", arg0, arg1, ...)` — macro shim that provides a
  typed callable surface (and helps in files that also define macros)

Important:

- Examples/snapshots are guarded by `-D reflaxe_rust_strict_examples` and will fail if `__rust__`
  leaks into user code via inlining.
