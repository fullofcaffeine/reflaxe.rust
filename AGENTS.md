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
- `Reflect`/`Any` policy (strict): avoid `Reflect.*` APIs and `Any`-typed payloads in first-party compiler/runtime/example code.
  Prefer typed fields/enums/interfaces; if an upstream/runtime boundary forces `Reflect` or `Any`, keep it tightly scoped and convert back to typed data immediately.
- For unavoidable stdlib API boundaries, prefer a descriptive `typedef` alias module (for example `*Types.cross.hx`)
  so raw `Dynamic` is centralized and documented instead of scattered across implementation files.
- Path privacy policy: never disclose machine-specific absolute local paths (for example `<home>/...`).
  Always use repository-relative paths; for sibling repos, use relative references like `../haxe.elixir.reference`.

## Meta (keep instructions current)

- When a new “gotcha”, policy decision, or workflow trick is discovered, write it down in the **closest scoped `AGENTS.md`** (add one if needed), not just in chat.
- Fix/test policy: after each fix, update tests and/or add a regression test (snapshots, runtime tests, or example test harness), unless an existing test update already covers the behavior change.

## Documentation (HaxeDoc)

- For any **vital** or **complex** type/function (compiler, runtime, `std/` interop surface), write **didactic HaxeDoc** using a clear **Why / What / How** structure.
- Be intentionally verbose when it prevents misuse (ownership/borrowing, injection rules, Cargo metadata, `@:coreType`/extern semantics, etc.).
- If you use a **non-trivial Haxe feature** (extern overrides, abstracts, `@:from/@:to`, macros, metadata-driven behavior, `@:native`, `@:coreType`, `@:enum abstract`, typed-ast patterns, etc.), add **comprehensive** HaxeDoc explaining why it exists and how it affects codegen/runtime semantics.
- This repo is a **reference compiler** for backend authors: every non-obvious compiler/runtime/std design decision should be documented where it lives, with explicit tradeoffs and rationale that other Haxe compiler implementers can follow.
- Boundary rule: whenever code crosses an unavoidable dynamic/native boundary (`Dynamic`, `extern`, `untyped __rust__`, runtime FFI), add HaxeDoc that states **why the boundary is required**, what typed shape is expected on each side, and how callers should return to typed code immediately after crossing it.
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
  - Unresolved-monomorph fallback policy:
    - User/project code now **errors by default** on unresolved monomorphs (avoid silent runtime-dynamic degradation).
    - Framework/upstream stdlib internals may still fall back to `Dynamic` as a compatibility bridge.
    - Escape hatch: `-D rust_allow_unresolved_monomorph_dynamic`.
    - Std warning audit switch remains: `-D rust_warn_unresolved_monomorph_std`.
  - Unmapped `@:coreType` fallback policy mirrors unresolved monomorphs:
    - User/project code errors by default; framework/upstream std may fallback to `Dynamic`.
    - Escape hatch: `-D rust_allow_unmapped_coretype_dynamic`.
    - Std warning audit switch: `-D rust_warn_unmapped_coretype_std`.
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
  - Nested catch-unwind gotcha: panic-output suppression in `hxrt::exception` must be depth-counted (not boolean).
    Inner `catch_unwind` frames can otherwise re-enable panic-hook output too early and leak noisy `Box<dyn Any>` lines
    even when throws are correctly caught by an outer frame (observed with socket `readLine` + server/client wrappers).
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
  - File suffix policy: upstream-colliding overrides under `std/` should use `.cross.hx` so they are selected only for cross/custom-target
    compilation, avoiding accidental pickup in eval/macro/non-target contexts.
  - Packaging gotcha: release packaging flattens `reflaxe.stdPaths` into `classPath` (`src/**`), so framework-stdlib detection must support both
    local layout (`std/**`) and packaged layout (`src/haxe/**`, `src/sys/**`, top-level std modules).
  - Path-alias gotcha: framework std detection must canonicalize absolute paths (`FileSystem.fullPath`) before prefix checks, otherwise
    symlink aliases (for example `/var/...` vs `/private/var/...`) can make packaged std overrides look like non-framework files and skip emission.
  - Validation gotcha: `.cross.hx` std override behavior must be validated through a real `-lib reflaxe.rust` install path (`haxelib newrepo` + `haxelib install <zip>`).
    A raw `-cp <pkg>/src` compile is not an equivalent packaging test and can resolve upstream std modules instead.
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
  - Default is portable output; enable more idiomatic output with `-D rust_idiomatic` or `-D reflaxe_rust_profile=idiomatic|rusty|metal`.
  - `-D rust_metal` is an alias for `-D reflaxe_rust_profile=metal`.
  - Metal policy: `reflaxe_rust_profile=metal` auto-enables strict app-boundary mode (`reflaxe_rust_strict`) so raw app-side `__rust__` is rejected by default.
    Typed framework facades in `src/reflaxe/rust/macros` and `std/rust/metal` remain allowed.
  - Optional formatter hook: `-D rustfmt` runs `cargo fmt --manifest-path <out>/Cargo.toml` after output generation (best-effort, warns on failure).
- TUI testing: prefer ratatui `TestBackend` via `TuiDemo.renderToString(...)` and assert in `cargo test` (see `docs/tui.md` and `examples/tui_todo/native/tui_tests.rs`).
  - Non-TTY gotcha: `TuiDemo.enter()` must never `unwrap()` terminal initialization. If interactive init fails (or stdin/stdout aren’t TTY), it must fall back to headless so `cargo run` in CI doesn’t panic.
  - Rust test harness gotcha: when using a shared `Mutex` in tests, recover poisoned locks with `lock().unwrap_or_else(|e| e.into_inner())` so one failing assertion does not cascade into unrelated `PoisonError` failures.
  - Path privacy gotcha: cleanup/util scripts should log repository-relative paths (not machine-absolute paths) to avoid leaking local filesystem details in terminal/CI logs.
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
- Run packaged-install smoke locally: `bash scripts/ci/package-smoke.sh` (build zip, install into local haxelib repo, compile, cargo build).
  - Regression coverage includes a symlinked working-directory compile pass to catch path-alias mismatches when classifying framework std files.
- Run HXRT overhead benchmarks locally: `bash scripts/ci/perf-hxrt-overhead.sh`
  - Refresh baseline intentionally: `bash scripts/ci/perf-hxrt-overhead.sh --update-baseline`
- Update a snapshot’s golden output (after review): `bash test/run-snapshots.sh --case <name> --update`
- Run the full CI-style harness locally (snapshots + all examples): `npm run test:all` (alias for `bash scripts/ci/harness.sh`)
  - Change-gate rule: for any non-trivial compiler/runtime/std/example code change, run the full harness (`npm run check:harness`)
    before marking work complete (unless explicitly scoped to docs-only or user-approved partial validation).
  - Convenience command: `npm run hooks:check:full` runs lint/docs guards plus the full harness.
  - Harness cleanup policy: by default, `scripts/ci/harness.sh` and `scripts/ci/windows-smoke.sh` clean generated `out*` folders and `.cache/*target*` on exit.
    - Keep artifacts intentionally for debugging with `KEEP_ARTIFACTS=1`.
    - Manual cleanup: `npm run clean:artifacts` (outputs only) and `npm run clean:artifacts:all` (outputs + caches).
- Install the repo pre-commit hook (gitleaks + guards + beads flush): run `bd hooks install` then `npm run hooks:install` (requires `gitleaks` installed)
- Dynamic policy guard: `scripts/lint/dynamic_usage_guard.sh` is part of hooks/CI and fails on any non-allowlisted `Dynamic` mention in first-party `*.hx`/`*.cross.hx` files.
  Keep intentional compatibility/runtime boundaries in `scripts/lint/dynamic_allowlist.txt` and remove avoidable `Dynamic` elsewhere.
  - Scan model: the guard is comment-aware; comment-only/doc-text mentions are ignored so the allowlist tracks code boundaries, not prose churn.
  - Compiler boundary-literal pattern: keep the unavoidable Haxe dynamic type-name literal centralized in
    `RustCompiler.dynamicBoundaryTypeName()` and route lookups/comparisons through it to prevent scattered allowlist churn.
  - Allowlist strictness: file-scoped entries must include an inline `# FILE_SCOPE_JUSTIFICATION: ...` comment in
    `scripts/lint/dynamic_allowlist.txt`; otherwise the guard fails during parsing.
- Runtime gotcha: snapshots embed `runtime/hxrt/**` into `test/snapshot/**/intended/hxrt/`, so any change under `runtime/hxrt/` requires `bash test/run-snapshots.sh --update` to keep goldens in sync.
- Snapshot runner gotcha: many snapshot crates share the same crate name (`hx_app`), so `test/run-snapshots.sh` must isolate `CARGO_TARGET_DIR` per case/variant
  (using a shared base cache) to avoid binary collisions and incorrect `stdout.txt` comparisons.
- `cargo hx` wrapper gotcha: when a smoke/test run compiles both the repo wrapper tool (`tools/hx`) and generated-template wrappers with a shared `CARGO_TARGET_DIR`,
  Cargo can reuse a binary compiled with the wrong `CARGO_MANIFEST_DIR` and resolve `scripts/dev/cargo-hx.sh` to the template copy.
  Keep wrapper-target dirs isolated for mixed-root/template checks (see `scripts/ci/template-smoke.sh`).
- Docs tracker gotcha: for progress-doc drift checks, compare docs before/after `npm run docs:sync:progress` (not against git HEAD) so checks work in dirty worktrees too.
- Docs tracker guard policy: `npm run docs:check:progress` must fail on stale tracker-backed docs even when `bd` is unavailable (fallback source is `.beads/issues.jsonl`, so keep tracker status commits synced via `bd sync`).
- Disk-space gotcha: full snapshot regeneration and full harness runs can consume many GB in `test/snapshot/**/out*`, `examples/**/out*`, Cargo caches/registries, and `.cache/examples-target`.
  If you hit `No space left on device`, run `npm run clean:artifacts:all` before re-running, then regenerate snapshots.
- Prefer DRY snapshot cases: use multiple `compile.<variant>.hxml` files in the same `test/snapshot/<case>/`
  directory (and `#if <define>` shims when needed) rather than duplicating snapshot directories for each profile.
  - Convention: `compile.hxml` → `out/` + `intended/`; `compile.rusty.hxml` → `out_rusty/` + `intended_rusty/`.
- Pre-push directive: keep `main` green by running the closest local equivalent of CI before `git push`:
  - `npm ci --ignore-scripts --no-audit --no-fund`
  - `bash test/run-snapshots.sh --clippy` (runs curated clippy checks on a small subset of snapshot crates)
  - `bash test/run-upstream-stdlib-sweep.sh` (curated upstream std imports under `-D rust_emit_upstream_std`)
  - `bash scripts/ci/perf-hxrt-overhead.sh` (soft-budget warnings + artifact report)
  - `cargo fmt && cargo clippy -- -D warnings`
  - Smoke-run any examples you touched (e.g. `(cd examples/tui_todo && haxe compile.hxml && (cd out && cargo run -q))`)
- CI runs:
  - `test/run-snapshots.sh` (runs `cargo fmt` + `cargo build -q` per snapshot)
  - `test/run-upstream-stdlib-sweep.sh` (per-module actionable compile/fmt/check for upstream std modules)
  - `scripts/ci/package-smoke.sh` validates the packaged artifact via isolated local `haxelib` install + Rust build (including symlink-cwd alias regression).
  - `scripts/ci/perf-hxrt-overhead.sh` benchmarks HXRT overhead (`hello`/`array`/`hot_loop`/`hot_loop_inproc` vs pure Rust baselines + chat profile spread) and emits soft-budget warnings + artifacts.
  - `scripts/ci/template-smoke.sh` scaffolds `templates/basic` via `scripts/dev/new-project.sh` and executes the full task-HXML matrix (`compile.build`, `compile`, `compile.run`, `compile.release`, `compile.release.run`).
  - CI shell-tooling compatibility: scripts must not hard-require `rg`; always keep a `grep`/`find` fallback.
    - Fallback test knob: set `REFLAXE_NO_RG=1` to force non-`rg` paths during local validation.
  - `scripts/ci/harness.sh` runs snapshots, metal boundary policy, upstream stdlib sweep, package smoke, template smoke, then compiles all non-CI example variants (`compile*.hxml`, excluding `*.ci.hxml`) and runs every CI variant present (`compile*.ci.hxml`, fallback `compile.hxml` when no CI file exists), including `cargo test` + `cargo run`.
  - `scripts/ci/windows-smoke.sh` runs on `windows-latest` and validates a Windows-safe subset (fmt/clippy + `hello_trace`/`sys_io` snapshots + `examples/sys_file_io` + `examples/sys_net_loopback`).

## Build (native)

- Default: compiling with `-D rust_output=...` generates Rust and runs `cargo build` (debug) best-effort.
- HXML default policy: new user-facing `compile*.hxml` files should compile+run by default via `-D rust_cargo_subcommand=run`
  (and usually `-D rust_cargo_quiet`), unless the file is explicitly CI/headless/build-only scoped.
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
- Dev watcher policy: `scripts/dev/watch-haxe-rust.sh` owns a session-local Haxe compile server in watch mode (`haxe --wait` + `--connect`) for fast incremental rebuilds.
  - Keep server ownership scoped to the watcher session (avoid attaching to external long-lived servers by default).
  - `--once` intentionally compiles directly by default.
  - Disable server mode explicitly with `--no-haxe-server` or `HAXE_RUST_WATCH_NO_SERVER=1` when debugging cache-related behavior.
  - Watch-mode cargo gotcha: normalize compile phase by mode (`run/test` force `-D rust_no_build`, `build` forces `rust_cargo_subcommand=build`) so task-style `.hxml` defaults (for example `rust_cargo_subcommand=run`) do not cause duplicate cargo invocations.
- Cargo task driver: use `cargo hx ...` (alias for `scripts/dev/cargo-hx.sh`) as a project-local runner (`compile -> cargo action`) instead of proliferating task-specific `compile.*.hxml` files.
  - Convenience aliasing: `examples/.cargo/config.toml` keeps `cargo hx ...` working from inside any `examples/<name>/` directory without extra flags.
  - Template parity: generated projects from `scripts/dev/new-project.sh` must include a local `cargo hx` alias/driver too (`templates/basic/.cargo/config.toml` + `templates/basic/scripts/dev/cargo-hx.sh`).

## Releases

- GitHub Actions:
  - `.github/workflows/ci.yml` runs on PRs/pushes to `main`.
  - `.github/workflows/release.yml` runs **semantic-release** after CI succeeds on `main` (semver tag + CHANGELOG + GitHub Release + zip asset).
  - `.github/workflows/rustsec.yml` runs `cargo audit` on a schedule.
  - Workspace gotcha: exclude `examples/` + `test/` + `.cache/` from the root workspace so `cargo fmt/build` works inside generated `*/out/` crates during snapshot and template-smoke runs.
- Packaging policy: `scripts/release/package-haxelib.sh` mirrors Reflaxe build flow by merging `reflaxe.stdPaths` into `classPath` and sanitizing `haxelib.json` (remove `reflaxe` field), while still shipping target-required `runtime/` + `vendor/`.
- Conventional commits are required on `main` so semantic-release can compute the next version.
  - Use `feat:` for minor, `fix:` for patch, and `feat!:` / `BREAKING CHANGE:` for major.
- Version strings are kept in sync by `scripts/release/sync-versions.js` (used by semantic-release).
