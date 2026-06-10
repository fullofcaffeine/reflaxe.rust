# Function values

## Why this matters

Portable Haxe code uses function values everywhere (callbacks, iterators, “Lambda”-style helpers, etc.).
The stable `1.x` portable contract supports *passing*, *storing*, and *calling* functions without
requiring application code to model Rust closure traits directly.

## What we support

Current support includes:

- Haxe function types (`A->B`, `(A,B)->C`, etc.) are lowered to:
  - shared runtime function handles (`crate::HxDynRef<dyn Fn(A, B, ...) -> R + Send + Sync>` in generated Rust)
- Haxe function literals (`function(...) ...`) are lowered to:
  - owned closures stored behind that shared function-handle representation
- When a function *value* is expected but the expression is a Rust function item/path,
  the compiler wraps it into the shared function-handle representation automatically.
- `this.method` function values are supported.
  - The compiler captures an owned receiver handle and emits a callable closure with the correct
    Rust receiver dispatch.
- Upstream-style Haxe `dynamic function` members are supported.
  - The compiler lowers them to stored function-value backing fields plus wrapper methods, so both
  `obj.onData = fn` assignment and subclass overrides work.
  - This is the mechanism used by `std/haxe/http/HttpBase.cross.hx`.
- Reusable callback values are supported.
  - Passing the same callback through multiple calls, storing it in locals, and forwarding it
    through higher-order helpers keeps the original Haxe value usable.
- Mutable captured-local callback patterns are supported on the current portable contract.
  - When a closure mutates a captured outer local, the compiler lowers that captured state through
    a shared-cell path so later calls observe the updated value instead of a stale snapshot.

## How the contract works

- Generated closures still use `move` so they can be stored and passed safely into Rust-owned APIs.
- That does **not** mean ordinary Haxe callback reuse is move-only.
  - The compiler now treats function values as reusable shared handles, so by-value Rust calls and
    local rebindings clone the handle when needed instead of moving the only copy away.
- The public Haxe contract stays callback-shaped.
  - You do not need to opt into `rust.*` APIs or manually model `Fn` / `FnMut` just to write
    normal portable Haxe callbacks.

## Constraints (important)

The remaining constraints are now narrower than “mutable callbacks might not work”:

- The stable contract is about Haxe function values, not arbitrary Rust closure trait interop.
  - Generated code uses the Rust `Fn` family internally because that is the callable shape the
    backend owns today.
  - If a future Rust-native surface genuinely needs `FnMut` or `FnOnce`, that should be exposed as
    an explicit Rust-first API, not smuggled into the portable contract.
- Function values are still subject to the normal portable/native boundary rules.
  - Portable code should use ordinary Haxe function types.
  - Rust-native callback abstractions remain backend-local and must stay explicit.

## Evidence

Decisive semantic fixtures:

- `test/semantic_diff/function_value_mutable_callbacks`
- `test/semantic_diff/closure_capture_mutation`
- `test/semantic_diff/this_method_closure`

Shape snapshots:

- `test/snapshot/function_values_basic`
- `test/snapshot/function_values_return`
