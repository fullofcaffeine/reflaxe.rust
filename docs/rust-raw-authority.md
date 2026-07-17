# Typed Rust IR and raw-authority closure

The compiler has no compiler-owned raw Rust call sites. Paths, types, lifetimes, generics,
declarations, static storage, fallback expressions, traits, impls, associated items, and where
clauses remain structural until the printer owns their final punctuation.

The checked-in [inventory](rust-raw-authority-inventory.json) currently records three raw factory
calls, all at author-controlled boundaries:

- two source-owned calls for the configured `__rust__` target-code injection path;
- one metadata-owned call for the optional inner body supplied to `@:rustImpl`.

There is deliberately no compiler-owned raw factory. A synthesized default stays a typed
`RustExpr`, and an unsupported recovery expression stays a typed `todo!()` macro call. Static
backing storage is four structural declarations. `RustItemGroup` preserves their historical
single-newline layout without turning them back into an opaque string.

## Why the inventory is generated

[`rust-raw-authority-policy.json`](../rust-raw-authority-policy.json) is the structured source of
truth for the two admitted boundaries. It generates the private authority constructors and exact
factories in `RustAST.hx`, then inventories every production factory call under `src/`, `std/`, and
`runtime/`. This means a new call site changes a reviewed artifact instead of silently widening raw
authority.

Use:

```bash
npm run docs:sync:rust-raw-authority
npm run guard:rust-raw-authority
npm run test:rust-raw-authority
```

Generation is repeatable: the contract writes the Haxe block and inventory twice and requires
byte-for-byte identity. The pre-commit hook also rejects an unstaged generated inventory.

## What the guard proves

The policy verifies that:

- every admitted authority is source-owned or metadata-owned;
- no `RustCompilerRawReason`, `RawCompilerOwned`, `compilerAt`, or `compilerGenerated` surface can
  return;
- every production `RustRawCode.<factory>(...)` call uses a policy-generated exact factory;
- the generated inventory matches those call sites, including file, line, and enclosing function;
- the closed AST still exposes the structural path, type, declaration, trait/impl, static-storage,
  and fallback-expression contracts named by the policy.

The call-site inventory uses a small lexical scanner because Haxe does not expose a stable public
whole-module parser to this Node-based repository guard. The scanner masks comments and string
literals before recognizing the closed `RustRawCode.<factory>(...)` spelling, and the Haxe type
checker separately protects construction through the private constructor. If a stable whole-module
Haxe syntax-tree API or a maintained parser becomes part of the toolchain, replace this lexical
step with that parser; do not broaden the scanner into a second Haxe grammar.

## Public qualification

This is an internal compiler-IR closure, not a new general Haxe authoring API. The two source-facing
escape hatches keep their existing qualification:

- `@:rustImpl` marker headers are structural; a supplied body string remains experimental metadata
  authority.
- `__rust__` and `@:rustAllowRaw` remain narrow experimental escape hatches and do not become
  metal-clean merely because their ownership is explicit.

See [Interop](interop.md) for authoring guidance and
[Pre-1.0 compatibility review](pre-1.0-compatibility-review.md) for stability classification.
