# Extern And Lifetime-Island Cookbook

This cookbook shows the preferred pattern for Rust APIs that are valuable to metal code but too
Rust-specific to model directly in Haxe signatures today: lifetimes, HRTB, const generics,
associated types, macro-heavy setup, or tightly contained `unsafe`.

## The Rule

Keep application Haxe typed. Put Rust-only complexity in a small Rust island behind a typed Haxe
extern or facade.

Use this shape when:

- the Rust implementation needs explicit lifetimes or `for<'a>` bounds;
- the API needs macro setup or const-generic details that would become stringly Haxe;
- a safe public operation needs a small internal `unsafe` block;
- exposing a 1:1 Rust signature would force Haxe users into awkward source just to satisfy the
  backend.

Do not use this shape to bypass normal Haxe APIs, hide broad `Dynamic` payloads, or put raw Rust in
business logic.

## Minimal Layout

```text
MyFacade.hx
native/my_facade.rs
compile.hxml
```

```haxe
@:native("crate::my_facade::MyFacade")
@:rustExtraSrc("native/my_facade.rs")
extern class MyFacade {
  @:native("first_word_owned")
  public static function firstWord(text:String):String;
}
```

```rust
pub struct MyFacade;

impl MyFacade {
    pub fn first_word_owned(text: String) -> String {
        first_word_view(text.as_str()).to_string()
    }
}

fn first_word_view<'a>(text: &'a str) -> &'a str {
    text.split_whitespace().next().unwrap_or("")
}
```

The Haxe surface returns an owned `String`. The Rust island uses the borrowed view internally and
does not expose the lifetime parameter to Haxe.

## Metadata Checklist

- `@:native("crate::module::Type")` maps a Haxe extern class to the Rust module/type.
- `@:native("function_name")` maps a Haxe method to a Rust function when names differ.
- `@:rustExtraSrc("path/to/file.rs")` copies one Rust module into generated `src/`.
- `@:rustExtraSrcDir("path/to/dir")` copies a directory of `.rs` modules.
- `@:rustCargo({ name: "crate", version: "1", features: ["derive"] })` declares Cargo dependencies.
- `@:rustGeneric(...)` adds explicit Rust bounds on admitted generic extern methods.
- `@:rustImpl(...)` is for narrow trait impls on generated local types; prefer extern islands when
  the impl body becomes substantial or lifetime-heavy.

Prefer metadata on the owning facade type so Cargo and module ownership travel with the API instead
of living in app hxml files.

## Safe Wrapper Expectations

The Rust island should expose the smallest safe API that Haxe needs:

- return owned values or compiler-supported borrowed tokens, not arbitrary borrowed references;
- validate indices, nullability assumptions, encoding assumptions, and platform preconditions at the
  boundary;
- keep panics and `unsafe` internals contained behind a safe function contract;
- document any cost that the facade hides, such as allocation, clone, locking, or runtime handle use.

If the natural Rust result is borrowed, either use a scoped callback API in Haxe or return an owned
projection. Do not smuggle borrowed values out through `Dynamic`, raw pointers, or app-owned
`__rust__` snippets.

For Rust RAII guards, use [RAII guard and lifetime-island rules](raii-guard-lifetime-islands.md):
simple lexical lock guards can use scoped callbacks, while file/socket/transaction/parser guards stay
inside typed extern islands unless a dedicated scoped Haxe facade exists.

## Cargo Tests

For non-trivial islands, add Rust tests beside the helper module or in the generated crate fixture.
The snapshot harness already runs `cargo build`; richer behavior should also run `cargo test` through
an example or CI script when the island has parsing, unsafe code, or platform-sensitive behavior.

## Reference Fixture

`test/snapshot/metal_extern_lifetime_island` demonstrates the pattern:

- Haxe calls `LifetimeIsland.firstWord(...)` and `LifetimeIsland.allWordsAtLeast(...)`.
- `LifetimeIsland.hx` owns `@:native` and `@:rustExtraSrc`.
- `native/lifetime_island.rs` uses an internal lifetime-returning helper and an HRTB closure helper.
- The Haxe-facing API returns owned `String` / `Bool` values and contains no raw Rust.
