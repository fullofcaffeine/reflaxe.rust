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
- Prefer `import` (and small local `typedef` aliases when appropriate) to avoid verbose fully-qualified type paths in compiler code
  (example: avoid `reflaxe.rust.ast.RustAST.RustMatchArm` when `import reflaxe.rust.ast.RustAST.RustMatchArm` lets you use `RustMatchArm`).
- Prefer strong typing: avoid `Dynamic` in compiler/runtime/examples unless the upstream Haxe API forces it (for example `haxe.Json.parse`, cross-thread message payloads, exception catch-alls).
  When you must cross a `Dynamic` boundary, immediately validate/cast/convert into a typed structure (often a `typedef` schema) and keep the rest of the code typed.
- `Dynamic` policy (strict): use `Dynamic` only when explicitly justified by upstream std/API contracts or unavoidable runtime boundaries.
  Default to concrete `typedef`/class/abstract/external bindings and leverage Haxe’s type system end-to-end.
- Path privacy policy: never disclose machine-specific absolute local paths (for example `<home>/...`).
  Always use repository-relative paths; for sibling repos, use relative references like `../haxe.elixir.reference`.

## Meta (keep instructions current)

- When a new “gotcha”, policy decision, or workflow trick is discovered, write it down in the **closest scoped `AGENTS.md`** (add one if needed), not just in chat.
- Bugs: when fixing a bug, add a regression test if it fits (snapshots, runtime tests, or example test harness).

## Documentation (HaxeDoc)

- For any **vital** or **complex** type/function (compiler, runtime, `std/` interop surface), write **didactic HaxeDoc** using a clear **Why / What / How** structure.
- Be intentionally verbose when it prevents misuse (ownership/borrowing, injection rules, Cargo metadata, `@:coreType`/extern semantics, etc.).
- If you use a **non-trivial Haxe feature** (extern overrides, abstracts, `@:from/@:to`, macros, metadata-driven behavior, `@:native`, `@:coreType`, `@:enum abstract`, typed-ast patterns, etc.), add **comprehensive** HaxeDoc explaining why it exists and how it affects codegen/runtime semantics.
- Treat docs as part of the stability contract: if behavior changes, update the relevant HaxeDoc and (when applicable) `docs/*.md` + snapshots.

## Prior Art (local reference repos)

- Use `../haxe.elixir.reference` for patterns/APIs we previously used for the Haxe→Elixir target.
- Use `../haxe.elixir.codex` for the original Haxe→Elixir compiler implementation (**read-only; do not modify anything in that repo**).

## Important Lessons (POC)

- Reflaxe’s `Context.getMainExpr()` is only reliable when the consumer uses `-main <Class>` (don’t rely on a bare trailing `Main` line in `.hxml`).
- Use `BaseCompiler.setExtraFile()` for non-`.rs` outputs like `Cargo.toml` (the default OutputManager always appends `fileOutputExtension` for normal outputs).
- Haxe “multi-type modules” behave like `haxe.macro.Expr.*`: types in `RustAST.hx` are addressed as `RustAST.RustExpr`, `RustAST.RustFile`, etc.
- Keep generated Rust rustfmt-clean: avoid embedding extra trailing newlines in raw items and always end files with a final newline.
- Lint hygiene policy (default): snake_case all emitted members + locals/args, trim code after diverging ops (`throw/return/break/continue`), omit unused catch vars / unused `self_` params, and add crate-level `#![allow(dead_code)]` to keep `cargo build` warning-free.
  - Rust lint gotcha: emit `loop { ... }` instead of `while true { ... }` to stay warning-free under `#![deny(warnings)]` (`while_true`).
  - Stub trait methods that `todo!()` must use `_` argument patterns to avoid `unused_variables` under `#![deny(warnings)]`.
  - Enum-match gotcha: avoid emitting wildcard `unreachable!()` arms when the match is already exhaustive (Rust warns with `unreachable_patterns`).
  - Dynamic-runtime gotcha: prefer typed `std/hxrt/*` extern wrappers over raw `untyped __rust__` for runtime APIs returning `Dynamic`
    (example: `haxe.Json.parse`, `sys.thread.Thread.readMessage`) to avoid unresolved monomorph warnings.
  - Unresolved-monomorph warning policy: keep warnings for user/project code, but suppress them by default for framework/upstream stdlib internals
    (fallback to `Dynamic` is an intentional compatibility bridge there). To audit std warnings explicitly, enable `-D rust_warn_unresolved_monomorph_std`.
  - JSON boundary gotcha: do not `cast Json.parse(...)` directly to a typed anonymous structure in app/runtime code. The Rust runtime may return a `DynObject` representation that fails anon downcasts; decode through `Reflect.field` + typed validators at the boundary, then stay strongly typed.
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
- Inheritance method dispatch model: Rust does not “inherit” methods, so subclasses must synthesize concrete Rust methods for non-overridden base methods (compile the base body with `this` dispatch bound to the subclass). This avoids invalid calls like `Base::method(&RefCell<Sub>)` and eliminates `todo!()` stubs in base trait impls.
- Base traits include inherited methods: if `BTrait` includes inherited `A.foo`, then `impl BTrait for RefCell<C>` must implement `foo` even if `B` didn’t declare it; emit base-trait impl methods from the base trait surface (declared + inherited), not just `baseType.fields.get()`.
- `super.method(...)` compiles via per-base “super thunk” methods on the current class (`__hx_super_<base_mod>_<method>`), so base implementations can run with a `&RefCell<Current>` receiver.
- Self-arg naming: treat `TSuper` as “uses receiver” so functions that call `super.*` don’t emit `_self_` but still reference `self_`.
- Accessor naming for backing fields: when a field name starts with `_` (e.g. `_x`), avoid Rust `non_snake_case` warnings and collisions by mapping accessor suffixes to `u<count>_<name>` (e.g. `_x` → `u1_x`), rather than stripping underscores.
- Exceptions/try-catch: implemented via `hxrt::exception` using a panic-id + thread-local payload.
  - `throw v` → `hxrt::exception::throw(hxrt::dynamic::from(v))`
  - `try { a } catch(e:T) { b }` → `match hxrt::exception::catch_unwind(|| { a }) { Ok(v) => v, Err(ex) => ...downcast chain... }`
  - Current limitation: catch type matching is Rust `Any` downcast (exact Rust type), so catching a subclass from a base-typed trait object isn’t supported yet.
- To include external crates and hand-written Rust modules for demos/interop, use `-D rust_cargo_deps_file=...` + `-D rust_extra_src=...` (the compiler copies `*.rs` into `out/src/` and emits `mod <file>;` in `main.rs`).
- Prefer framework-driven metadata over `.hxml` wiring when possible:
  - `@:rustCargo(...)` declares Cargo deps from Haxe types.
  - `@:rustExtraSrc("path/to/file.rs")` / `@:rustExtraSrcDir("path/to/dir")` lets framework code ship Rust modules without requiring apps to set `-D rust_extra_src=...`.
  - For std overrides that need complex backend-specific setup (for example DB driver connection builders),
    prefer moving Rust-heavy constructors into typed extern modules (`std/hxrt/**` + `@:rustExtraSrc`) rather than inline `untyped __rust__` in Haxe methods.
- Rust module names must avoid keywords (e.g. class `Impl` becomes module `impl_`).
- Rust keyword escaping must include reserved keywords like `box` (Rust 2021); keep `RustNaming.KEYWORDS` / extra-src keyword checks in sync.
- Generics: Rust rejects unused type params on structs; emit a `PhantomData` field (e.g. `__hx_phantom`) when a class has type params not referenced by any instance fields.
- Constructors: lift leading `this.field = <arg>` assignments into the struct literal to avoid requiring `T: Default` for generic fields (and to reduce borrow-mut noise).
- Haxe desugaring/inlining introduces `_g*` temporaries; for `Array<T>` (mapped to `Vec<T>`), avoid accidental moves by cloning `_g* = <local array>` initializers/assignments.
- Use `Context.getAllModuleTypes()` (not `Context.getTypes()`) to enumerate generated module types for dependency closure / RTTI maps.
- Stdlib emission model (important for “full stdlib parity” work):
  - The compiler only emits Rust modules for **user project files** and this repo’s `std/` overrides (`isFrameworkStdFile`).
  - Upstream Haxe std files (the default `.../haxe/versions/<ver>/std/`) are *typed* but **not emitted** by default.
  - Consequence: any std API type that appears in emitted signatures (e.g. `sys.io.FileSeek`) must exist under `std/`
    (or the emission filter must be expanded intentionally).
- `Std.isOfType` is implemented as a compiler intrinsic (exact-type check via `__hx_type_id`, plus compile-time subtype short-circuit).
- String move semantics: many generated Rust functions take `String` by value; to preserve Haxe’s “strings are re-usable after calls” behavior, callsites currently clone String arguments based on the callee’s parameter types.
- Nullable-string migration gotcha: a full switch to `hxrt::string::HxString` as the emitted Rust `String` representation touches broad stdlib/runtime surfaces (notably map key types, `toString` trait bridges, and hardcoded `String` paths).
  Keep `-D rust_string_nullable` disabled on mainline until those compatibility points are fully migrated and covered by snapshots.
  - Concrete breakage pattern while the migration is incomplete: generated code can expect `HxString` while runtime/native APIs still take raw `String`
    (for example `hxrt::array::Array::join`, `sys.io.*.writeString/readLine`, `std::process::Command` args), producing large `E0308` type-mismatch cascades.
  - Interop guardrail: runtime APIs that conceptually accept string separators/paths/labels should prefer flexible signatures (`AsRef<str>`/`&str`) so both `String` and `hxrt::string::HxString` work without callsite churn.
    - Current concrete fix: `hxrt::array::Array::join` is generic over `AsRef<str>` and `HxString` implements `AsRef<str>`.
- Dynamic args: when calling a function expecting `Dynamic` (e.g. `Sys.println(v:Dynamic)`), the compiler boxes non-`Dynamic` args via `hxrt::dynamic::from(...)` and clones non-`Copy` inputs to avoid Rust moves.
- Nullable locals: when a `Null<T>` local is initialized to `null` and the **very next statement** assigns it, codegen elides the initial `None` to avoid Rust `unused_assignments` / `unused_mut` warnings (see `test/snapshot/null_optional_args`).
- Extern bindings: for `extern class` types, `@:native("some::rust::path")` maps the class to a Rust path, and `@:native("fn_name")` maps fields/methods.
  - Gotcha: Haxe may rewrite names and store the original in `:realPath`; for extern fields, prefer the post-metadata identifier (`cf.name`) unless `@:native(...)` overrides it.
- `haxe.io.Bytes` override is `extern` to prevent stdlib inlining; keep its Rust mapping (`HxRef<hxrt::bytes::Bytes>`) as a special-case that must win over generic extern-path mapping.
- Properties vs storage:
  - Only **physical** vars are emitted as Rust struct fields. Non-storage properties (`get/set`, `get/never`, etc.) are lowered to accessor calls.
  - Property assignments must return the setter return value (Haxe semantics), not necessarily the raw RHS.
  - Storage-backed accessors (`default,get` / `default,set`) commonly use `return x = v;` in Haxe; codegen must treat `x` inside `get_x`/`set_x` as direct backing-field access to avoid recursive calls.
  - In inherited method shims, the typed AST may type `this` as the base class; for property/field lowering, treat `this` as `currentClassType` (the concrete class being compiled) to avoid calling base methods with `&RefCell<Sub>` receivers.
- Profiles:
  - Default is portable output; enable more idiomatic output with `-D rust_idiomatic` or `-D reflaxe_rust_profile=idiomatic|rusty`.
  - Optional formatter hook: `-D rustfmt` runs `cargo fmt --manifest-path <out>/Cargo.toml` after output generation (best-effort, warns on failure).
- TUI testing: prefer ratatui `TestBackend` via `TuiDemo.renderToString(...)` and assert in `cargo test` (see `docs/tui.md` and `examples/tui_todo/native/tui_tests.rs`).
  - Non-TTY gotcha: `TuiDemo.enter()` must never `unwrap()` terminal initialization. If interactive init fails (or stdin/stdout aren’t TTY), it must fall back to headless so `cargo run` in CI doesn’t panic.
  - Harness linkage gotcha: keep `Harness.__link()` reachable in all compile variants (not only `tui_headless`) so Rust tests that call `crate::harness::*` compile in both dev and CI outputs.
- `@:coreApi` gotcha: core types must match upstream public API exactly. Any extra helpers must be private.
  - Use `@:allow(...)`/`@:access(...)` to make private helpers usable by sibling std types.
  - Backend rule: private members in an `@:allow/@:access` class are emitted as `pub(crate)` in Rust so cross-module calls compile.
- Threading (sys.thread): implemented with a thread-safe heap (`HxRef<T>` is `Arc<...>` + locking) so Haxe values can cross OS threads safely.
  - `sys.thread.Thread` + core primitives exist; `sys.thread.EventLoop` is runtime-backed. See `docs/threading.md`.

## Testing + CI

- Run snapshots locally: `bash test/run-snapshots.sh`
- Run upstream stdlib sweep locally: `bash test/run-upstream-stdlib-sweep.sh` (or single-module: `--module haxe.Json`).
- Run Windows-safe smoke subset locally: `bash scripts/ci/windows-smoke.sh` (same subset used by the Windows CI job).
- Update a snapshot’s golden output (after review): `bash test/run-snapshots.sh --case <name> --update`
- Run the full CI-style harness locally (snapshots + all examples): `npm run test:all` (alias for `bash scripts/ci/harness.sh`)
  - Harness cleanup policy: by default, `scripts/ci/harness.sh` and `scripts/ci/windows-smoke.sh` clean generated `out*` folders and `.cache/*target*` on exit.
    - Keep artifacts intentionally for debugging with `KEEP_ARTIFACTS=1`.
    - Manual cleanup: `npm run clean:artifacts` (outputs only) and `npm run clean:artifacts:all` (outputs + caches).
- Install the repo pre-commit hook (gitleaks + guards + beads flush): run `bd hooks install` then `npm run hooks:install` (requires `gitleaks` installed)
- Runtime gotcha: snapshots embed `runtime/hxrt/**` into `test/snapshot/**/intended/hxrt/`, so any change under `runtime/hxrt/` requires `bash test/run-snapshots.sh --update` to keep goldens in sync.
- Snapshot runner gotcha: many snapshot crates share the same crate name (`hx_app`), so `test/run-snapshots.sh` must isolate `CARGO_TARGET_DIR` per case/variant
  (using a shared base cache) to avoid binary collisions and incorrect `stdout.txt` comparisons.
- Disk-space gotcha: full snapshot regeneration and full harness runs can consume many GB in `test/snapshot/**/out*`, `examples/**/out*`, Cargo caches/registries, and `.cache/examples-target`.
  If you hit `No space left on device`, run `npm run clean:artifacts:all` before re-running, then regenerate snapshots.
- Prefer DRY snapshot cases: use multiple `compile.<variant>.hxml` files in the same `test/snapshot/<case>/`
  directory (and `#if <define>` shims when needed) rather than duplicating snapshot directories for each profile.
  - Convention: `compile.hxml` → `out/` + `intended/`; `compile.rusty.hxml` → `out_rusty/` + `intended_rusty/`.
- Pre-push directive: keep `main` green by running the closest local equivalent of CI before `git push`:
  - `npm ci --ignore-scripts --no-audit --no-fund`
  - `bash test/run-snapshots.sh --clippy` (runs curated clippy checks on a small subset of snapshot crates)
  - `bash test/run-upstream-stdlib-sweep.sh` (curated upstream std imports under `-D rust_emit_upstream_std`)
  - `cargo fmt && cargo clippy -- -D warnings`
  - Smoke-run any examples you touched (e.g. `(cd examples/tui_todo && haxe compile.hxml && (cd out && cargo run -q))`)
- CI runs:
  - `test/run-snapshots.sh` (runs `cargo fmt` + `cargo build -q` per snapshot)
  - `test/run-upstream-stdlib-sweep.sh` (per-module actionable compile/fmt/check for upstream std modules)
  - `scripts/ci/harness.sh` compiles developer variants (`compile.hxml`, `compile.rusty.hxml`) and runs a CI matrix across all `examples/*` (`compile.ci.hxml` or fallback `compile.hxml`, plus `compile.rusty.ci.hxml` when present), including `cargo test` + `cargo run`.
  - `scripts/ci/windows-smoke.sh` runs on `windows-latest` and validates a Windows-safe subset (fmt/clippy + `hello_trace`/`sys_io` snapshots + `examples/sys_file_io` + `examples/sys_net_loopback`).

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
