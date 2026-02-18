# Haxe-Authored Rust Tests (`@:rustTest`)

`reflaxe.rust` supports authoring Rust test cases directly in Haxe.

## Why

- Keep tests in typed Haxe alongside app/compiler code.
- Still run through native `cargo test` and Rust tooling.
- Avoid maintaining duplicate test logic in `native/*.rs`.

## What

Annotate a `public static` method with `@:rustTest`:

- Method must have **zero parameters**.
- Return type must be **`Void`** or **`Bool`**.
  - `Void`: wrapper passes when the method completes without throw/panic.
  - `Bool`: wrapper emits `assert!(...)`.

Supported metadata forms:

- `@:rustTest`
- `@:rustTest("custom_name")`
- `@:rustTest({ name: "custom_name", serial: false })`

Default behavior:

- Wrapper name is generated from class + method (snake_case).
- `serial` defaults to `true` (shared lock to avoid stateful-test races).

## How it is emitted

During compilation, the backend collects `@:rustTest` methods and emits:

- `#[cfg(test)] mod __hx_tests` in `main.rs`
- One Rust `#[test]` wrapper per Haxe test method
- Optional shared `OnceLock<Mutex<()>>` lock for serialized tests

Wrapper call shape:

- `crate::<module>::<Type>::<method>()`

This is why tests must live in **non-main classes** (the main class emits free functions, not an impl type).

## Boundary notes

- Tests remain fully typed in Haxe.
- No app-side `__rust__` is required.
- Failures propagate as normal Rust test failures (`panic` / failed assert), so CI output stays native and familiar.

## Example references

- `examples/profile_storyboard/StoryboardTests.hx` contains a didactic `@:rustTest` HaxeDoc reference
  that documents `name`/`serial` metadata usage in-place.
- `examples/chat_loopback/ChatTests.hx` and `examples/tui_todo/TuiTests.hx` show larger real-app suites
  using the same contract.
