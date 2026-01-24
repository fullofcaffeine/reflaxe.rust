# AI/Agent Instructions for `reflaxe.rust`

## Issue Tracking

This project uses **bd (beads)** for issue tracking.

- `bd prime` — workflow context
- `bd ready` — unblocked work
- `bd show <id>` — details
- `bd update <id> --status in_progress` — claim
- `bd close <id>` — complete
- `bd sync` — sync to git (once a remote is configured)

Milestone plan lives in Beads under epic `haxe.rust-oo3` (see `bd graph haxe.rust-oo3 --compact`).

## Product Source of Truth

- Requirements + architecture: `prd.md`
- Target: **Haxe 4.3.7 → Rust** via Reflaxe

## Core Guardrails (compiler)

- Keep the pipeline **AST-first**: Builder → Transformer passes → Printer (avoid string-gen except at the printer).
- Prefer typed analysis + passes over regex/string heuristics.
- Portable mode first; keep a single runtime abstraction point so backends can evolve (e.g., `HxRef<T>`).

## Meta (keep instructions current)

- When a new “gotcha”, policy decision, or workflow trick is discovered, write it down in the **closest scoped `AGENTS.md`** (add one if needed), not just in chat.

## Prior Art (local reference repos)

- Use `<home>/workspace/code/haxe.elixir.reference` for patterns/APIs we previously used for the Haxe→Elixir target.
- Use `<home>/workspace/code/haxe.elixir.codex` for the original Haxe→Elixir compiler implementation (**read-only; do not modify anything in that repo**).

## Important Lessons (POC)

- Reflaxe’s `Context.getMainExpr()` is only reliable when the consumer uses `-main <Class>` (don’t rely on a bare trailing `Main` line in `.hxml`).
- Use `BaseCompiler.setExtraFile()` for non-`.rs` outputs like `Cargo.toml` (the default OutputManager always appends `fileOutputExtension` for normal outputs).
- Haxe “multi-type modules” behave like `haxe.macro.Expr.*`: types in `RustAST.hx` are addressed as `RustAST.RustExpr`, `RustAST.RustFile`, etc.
- Keep generated Rust rustfmt-clean: avoid embedding extra trailing newlines in raw items and always end files with a final newline.
- The generated crate always includes the bundled runtime crate at `./hxrt` and adds `hxrt = { path = "./hxrt" }` to `Cargo.toml`.
- For class instance semantics, the current POC uses `type HxRef<T> = Rc<RefCell<T>>` and:
  - concrete calls use `Class::method(&obj, ...)` where methods take `&RefCell<Class>`
  - polymorphic base/interface calls use trait objects (`Rc<dyn ...>`) and `obj.method(...)` dispatch
- For field assignment on `HxRef` (`obj.field = rhs`), evaluate `rhs` first, then take `borrow_mut()` (otherwise `RefCell` will panic at runtime when `rhs` reads other fields).
- For void Haxe functions, don’t emit a tail expression just because the last expression has a non-void type (e.g. `OpAssign` is typed as the RHS); pass the expected return type into block compilation to decide whether a tail is allowed.
- Escape hatch policy: **apps/examples should not use `__rust__` directly**. Put injections behind Haxe APIs in `std/` and keep examples “pure”.
  - Repo enforcement: `-D reflaxe_rust_strict_examples` (used by `examples/**` and `test/snapshot/**`).
  - Opt-in user enforcement: `-D reflaxe_rust_strict`.
- `__rust__` can be called without a prefix as `untyped __rust__("...")` (like Elixir’s `untyped __elixir__`). `reflaxe.rust.macros.RustInjection.__rust__` is an optional macro shim that:
  - keeps a typed callable surface (no `untyped` at callsites)
  - supports Reflaxe `{0}` placeholder interpolation with varargs (`RustInjection.__rust__("foo({0})", arg0)`)
- Reflaxe injection gotcha: `TargetCodeInjection.checkTargetCodeInjectionGeneric` returns an empty list when the injected string has no `{0}` placeholders. The compiler must treat that case as “literal injection string”.
- Exceptions/try-catch: implemented via `hxrt::exception` using a panic-id + thread-local payload.
  - `throw v` → `hxrt::exception::throw(hxrt::dynamic::from(v))`
  - `try { a } catch(e:T) { b }` → `match hxrt::exception::catch_unwind(|| { a }) { Ok(v) => v, Err(ex) => ...downcast chain... }`
  - Current limitation: catch type matching is Rust `Any` downcast (exact Rust type), so catching a subclass from a base-typed trait object isn’t supported yet.
- To include external crates and hand-written Rust modules for demos/interop, use `-D rust_cargo_deps_file=...` + `-D rust_extra_src=...` (the compiler copies `*.rs` into `out/src/` and emits `mod <file>;` in `main.rs`).
- Rust module names must avoid keywords (e.g. class `Impl` becomes module `impl_`).
- Use `Context.getAllModuleTypes()` (not `Context.getTypes()`) to enumerate generated module types for dependency closure / RTTI maps.
- `Std.isOfType` is implemented as a compiler intrinsic (exact-type check via `__hx_type_id`, plus compile-time subtype short-circuit).
- String move semantics: many generated Rust functions take `String` by value; to preserve Haxe’s “strings are re-usable after calls” behavior, callsites currently clone String arguments based on the callee’s parameter types.
- Dynamic args: when calling a function expecting `Dynamic` (e.g. `Sys.println(v:Dynamic)`), the compiler boxes non-`Dynamic` args via `hxrt::dynamic::from(...)` and clones non-`Copy` inputs to avoid Rust moves.
- Extern bindings: for `extern class` types, `@:native("some::rust::path")` maps the class to a Rust path, and `@:native("fn_name")` maps fields/methods.
  - Gotcha: Haxe may rewrite names and store the original in `:realPath`; for extern fields, prefer the post-metadata identifier (`cf.name`) unless `@:native(...)` overrides it.
- `haxe.io.Bytes` override is `extern` to prevent stdlib inlining; keep its Rust mapping (`HxRef<hxrt::bytes::Bytes>`) as a special-case that must win over generic extern-path mapping.
- Profiles:
  - Default is portable output; enable more idiomatic output with `-D rust_idiomatic` or `-D reflaxe_rust_profile=idiomatic|rusty`.
  - Optional formatter hook: `-D rustfmt` runs `cargo fmt --manifest-path <out>/Cargo.toml` after output generation (best-effort, warns on failure).

## Testing + CI

- Run snapshots locally: `bash test/run-snapshots.sh`
- Update a snapshot’s golden output (after review): `bash test/run-snapshots.sh --case <name> --update`
- CI runs:
  - `test/run-snapshots.sh` (runs `cargo fmt` + `cargo build -q` per snapshot)
  - example smoke runs (`examples/hello`, `examples/classes`)

## Tooling (lix)

- This repo uses **lix** for a pinned Haxe toolchain (see `.haxerc`).
- `haxe_libraries/reflaxe.rust.hxml` is a self-referential config so `-lib reflaxe.rust` works in `test/**` and `examples/**` without `haxelib dev`.
- `test/run-snapshots.sh` prefers the project-local Haxe binary at `node_modules/.bin/haxe` when available (override with `HAXE_BIN=...`).

## Releases

- GitHub Actions:
  - `.github/workflows/ci.yml` runs on PRs/pushes to `main`.
  - `.github/workflows/release.yml` runs on tags `v*` and publishes a GitHub Release with a haxelib zip.
- Tag/version policy: tag `vX.Y.Z` must match `haxelib.json` `"version": "X.Y.Z"`.
- Package locally: `bash scripts/release/package-haxelib.sh dist/reflaxe.rust.zip`
- Optional: set `HAXELIB_PASSWORD` secret to auto-publish to haxelib on tag releases.
