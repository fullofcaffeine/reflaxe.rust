# AI/Agent Instructions for `reflaxe.rust`

## Issue Tracking

This project uses **bd (beads)** for issue tracking.

- `bd prime` — workflow context
- `bd ready` — unblocked work
- `bd show <id>` — details
- `bd update <id> --status in_progress` — claim
- `bd close <id>` — complete
- `bd sync` — sync to git (once a remote is configured)

Gotcha: `bd` DB state and `.beads/issues.jsonl` can drift depending on bd daemon/auto-flush settings.
Before committing bead status changes, run `bd sync` and ensure `.beads/issues.jsonl` is included in the commit when modified.

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

## Documentation (HaxeDoc)

- For any **vital** or **complex** type/function (compiler, runtime, `std/` interop surface), write **didactic HaxeDoc** using a clear **Why / What / How** structure.
- Be intentionally verbose when it prevents misuse (ownership/borrowing, injection rules, Cargo metadata, `@:coreType`/extern semantics, etc.).
- If you use a **non-trivial Haxe feature** (extern overrides, abstracts, `@:from/@:to`, macros, metadata-driven behavior, `@:native`, `@:coreType`, `@:enum abstract`, typed-ast patterns, etc.), add **comprehensive** HaxeDoc explaining why it exists and how it affects codegen/runtime semantics.
- Treat docs as part of the stability contract: if behavior changes, update the relevant HaxeDoc and (when applicable) `docs/*.md` + snapshots.

## Prior Art (local reference repos)

- Use `<home>/workspace/code/haxe.elixir.reference` for patterns/APIs we previously used for the Haxe→Elixir target.
- Use `<home>/workspace/code/haxe.elixir.codex` for the original Haxe→Elixir compiler implementation (**read-only; do not modify anything in that repo**).

## Important Lessons (POC)

- Reflaxe’s `Context.getMainExpr()` is only reliable when the consumer uses `-main <Class>` (don’t rely on a bare trailing `Main` line in `.hxml`).
- Use `BaseCompiler.setExtraFile()` for non-`.rs` outputs like `Cargo.toml` (the default OutputManager always appends `fileOutputExtension` for normal outputs).
- Haxe “multi-type modules” behave like `haxe.macro.Expr.*`: types in `RustAST.hx` are addressed as `RustAST.RustExpr`, `RustAST.RustFile`, etc.
- Keep generated Rust rustfmt-clean: avoid embedding extra trailing newlines in raw items and always end files with a final newline.
- Lint hygiene policy (default): snake_case all emitted members + locals/args, trim code after diverging ops (`throw/return/break/continue`), omit unused catch vars / unused `self_` params, and add crate-level `#![allow(dead_code)]` to keep `cargo build` warning-free.
  - Rust lint gotcha: emit `loop { ... }` instead of `while true { ... }` to stay warning-free under `#![deny(warnings)]` (`while_true`).
  - Stub trait methods that `todo!()` must use `_` argument patterns to avoid `unused_variables` under `#![deny(warnings)]`.
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
- `rust.Ref<T>` / `rust.MutRef<T>` use `@:from` (typically lowered to `cast`) so Haxe typing can pass `T` where refs are expected; codegen must still emit `&` / `&mut` even when the typed expression becomes `TCast(...)`.
- Rust naming collisions across inheritance must preserve base-field names: assign names in base→derived order and only disambiguate derived names against already-used base names.
- Exceptions/try-catch: implemented via `hxrt::exception` using a panic-id + thread-local payload.
  - `throw v` → `hxrt::exception::throw(hxrt::dynamic::from(v))`
  - `try { a } catch(e:T) { b }` → `match hxrt::exception::catch_unwind(|| { a }) { Ok(v) => v, Err(ex) => ...downcast chain... }`
  - Current limitation: catch type matching is Rust `Any` downcast (exact Rust type), so catching a subclass from a base-typed trait object isn’t supported yet.
- To include external crates and hand-written Rust modules for demos/interop, use `-D rust_cargo_deps_file=...` + `-D rust_extra_src=...` (the compiler copies `*.rs` into `out/src/` and emits `mod <file>;` in `main.rs`).
- Prefer framework-driven metadata over `.hxml` wiring when possible:
  - `@:rustCargo(...)` declares Cargo deps from Haxe types.
  - `@:rustExtraSrc("path/to/file.rs")` / `@:rustExtraSrcDir("path/to/dir")` lets framework code ship Rust modules without requiring apps to set `-D rust_extra_src=...`.
- Rust module names must avoid keywords (e.g. class `Impl` becomes module `impl_`).
- Rust keyword escaping must include reserved keywords like `box` (Rust 2021); keep `RustNaming.KEYWORDS` / extra-src keyword checks in sync.
- Generics: Rust rejects unused type params on structs; emit a `PhantomData` field (e.g. `__hx_phantom`) when a class has type params not referenced by any instance fields.
- Constructors: lift leading `this.field = <arg>` assignments into the struct literal to avoid requiring `T: Default` for generic fields (and to reduce borrow-mut noise).
- Haxe desugaring/inlining introduces `_g*` temporaries; for `Array<T>` (mapped to `Vec<T>`), avoid accidental moves by cloning `_g* = <local array>` initializers/assignments.
- Use `Context.getAllModuleTypes()` (not `Context.getTypes()`) to enumerate generated module types for dependency closure / RTTI maps.
- `Std.isOfType` is implemented as a compiler intrinsic (exact-type check via `__hx_type_id`, plus compile-time subtype short-circuit).
- String move semantics: many generated Rust functions take `String` by value; to preserve Haxe’s “strings are re-usable after calls” behavior, callsites currently clone String arguments based on the callee’s parameter types.
- Dynamic args: when calling a function expecting `Dynamic` (e.g. `Sys.println(v:Dynamic)`), the compiler boxes non-`Dynamic` args via `hxrt::dynamic::from(...)` and clones non-`Copy` inputs to avoid Rust moves.
- Nullable locals: when a `Null<T>` local is initialized to `null` and the **very next statement** assigns it, codegen elides the initial `None` to avoid Rust `unused_assignments` / `unused_mut` warnings (see `test/snapshot/null_optional_args`).
- Extern bindings: for `extern class` types, `@:native("some::rust::path")` maps the class to a Rust path, and `@:native("fn_name")` maps fields/methods.
  - Gotcha: Haxe may rewrite names and store the original in `:realPath`; for extern fields, prefer the post-metadata identifier (`cf.name`) unless `@:native(...)` overrides it.
- `haxe.io.Bytes` override is `extern` to prevent stdlib inlining; keep its Rust mapping (`HxRef<hxrt::bytes::Bytes>`) as a special-case that must win over generic extern-path mapping.
- Profiles:
  - Default is portable output; enable more idiomatic output with `-D rust_idiomatic` or `-D reflaxe_rust_profile=idiomatic|rusty`.
  - Optional formatter hook: `-D rustfmt` runs `cargo fmt --manifest-path <out>/Cargo.toml` after output generation (best-effort, warns on failure).
- TUI testing: prefer ratatui `TestBackend` via `TuiDemo.renderToString(...)` and assert in `cargo test` (see `docs/tui.md` and `examples/tui_todo/native/tui_tests.rs`).
  - Non-TTY gotcha: `TuiDemo.enter()` must never `unwrap()` terminal initialization. If interactive init fails (or stdin/stdout aren’t TTY), it must fall back to headless so `cargo run` in CI doesn’t panic.

## Testing + CI

- Run snapshots locally: `bash test/run-snapshots.sh`
- Update a snapshot’s golden output (after review): `bash test/run-snapshots.sh --case <name> --update`
- Runtime gotcha: snapshots embed `runtime/hxrt/**` into `test/snapshot/**/intended/hxrt/`, so any change under `runtime/hxrt/` requires `bash test/run-snapshots.sh --update` to keep goldens in sync.
- Prefer DRY snapshot cases: use multiple `compile.<variant>.hxml` files in the same `test/snapshot/<case>/`
  directory (and `#if <define>` shims when needed) rather than duplicating snapshot directories for each profile.
  - Convention: `compile.hxml` → `out/` + `intended/`; `compile.rusty.hxml` → `out_rusty/` + `intended_rusty/`.
- Pre-push directive: keep `main` green by running the closest local equivalent of CI before `git push`:
  - `npm ci --ignore-scripts --no-audit --no-fund`
  - `bash test/run-snapshots.sh`
  - `cargo fmt && cargo clippy -- -D warnings`
  - Smoke-run any examples you touched (e.g. `(cd examples/tui_todo && haxe compile.hxml && (cd out && cargo run -q))`)
- CI runs:
  - `test/run-snapshots.sh` (runs `cargo fmt` + `cargo build -q` per snapshot)
  - example smoke runs (`examples/hello`, `examples/classes`)

## Build (native)

- Default: compiling with `-D rust_output=...` generates Rust and runs `cargo build` (debug) best-effort.
- The generated Cargo crate emits a minimal `.gitignore` by default (opt-out: `-D rust_no_gitignore`).
- Codegen-only: add `-D rust_no_build` (alias: `-D rust_codegen_only`).
- Deny warnings (opt-in): add `-D rust_deny_warnings` to emit `#![deny(warnings)]` in the generated crate root.
- Release: add `-D rust_build_release` / `-D rust_release`.
- Optional target triple: `-D rust_target=x86_64-unknown-linux-gnu` (passed to `cargo build --target ...`).
- Cargo/tooling knobs (for parity with other targets’ tool scaffolding):
  - `-D rust_cargo_subcommand=build|check|test|clippy|run` (default: `build`)
  - `-D rust_cargo_features=feat1,feat2`
  - `-D rust_cargo_no_default_features`, `-D rust_cargo_all_features`
  - `-D rust_cargo_locked`, `-D rust_cargo_offline`, `-D rust_cargo_quiet`
  - `-D rust_cargo_jobs=8`
  - `-D rust_cargo_target_dir=...` (sets `CARGO_TARGET_DIR`)

## Tooling (lix)

- This repo uses **lix** for a pinned Haxe toolchain (see `.haxerc`).
- `haxe_libraries/reflaxe.rust.hxml` is a self-referential config so `-lib reflaxe.rust` works in `test/**` and `examples/**` without `haxelib dev`.
- `test/run-snapshots.sh` prefers the project-local Haxe binary at `node_modules/.bin/haxe` when available (override with `HAXE_BIN=...`).

## Releases

- GitHub Actions:
  - `.github/workflows/ci.yml` runs on PRs/pushes to `main`.
  - `.github/workflows/release.yml` runs **semantic-release** after CI succeeds on `main` (semver tag + CHANGELOG + GitHub Release + zip asset).
  - `.github/workflows/rustsec.yml` runs `cargo audit` on a schedule.
  - Workspace gotcha: exclude `examples/` + `test/` from the root workspace so `cargo fmt/build` works inside generated `*/out/` crates during snapshot tests.
- Conventional commits are required on `main` so semantic-release can compute the next version.
  - Use `feat:` for minor, `fix:` for patch, and `feat!:` / `BREAKING CHANGE:` for major.
- Version strings are kept in sync by `scripts/release/sync-versions.js` (used by semantic-release).
