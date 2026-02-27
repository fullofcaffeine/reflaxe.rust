# PRD: reflaxe.rust (Haxe 4.3.7 -> Rust)

## 1) Product summary

`reflaxe.rust` compiles Haxe to Rust using two explicit contracts:

- `portable` (default): portability-first Haxe semantics.
- `metal`: Rust-first contract for strict boundaries and performance-sensitive code paths.

The backend is AST-first (lowering + passes + printer), ships with runtime feature planning/reporting,
and enforces typed interop policies intended for production use.

## 2) Core goals

1. Preserve predictable Haxe behavior in `portable`.
2. Provide a strict, typed Rust-first lane in `metal`.
3. Keep generated Rust deterministic and auditable (snapshot + report artifacts).
4. Keep runtime overhead visible and continuously tracked in CI.

## 3) Contract model

### Portable contract

- Default profile.
- Nullable string representation by default.
- Warnings for native-target imports (`rust.*`, `cpp.*`, etc.) with strict escalation available.
- Supports `@:haxeMetal` lane metadata for metal-island enforcement inside portable builds.

### Metal contract

- Enabled with `-D reflaxe_rust_profile=metal`.
- Strict app-boundary mode auto-enabled (`reflaxe_rust_strict`).
- Non-null string contract by default:
  - `String` cannot be assigned `null` directly.
  - Use `Null<String>` for nullable values.
  - `-D rust_string_nullable` is explicit fallback mode (policy-controlled).
- Optional minimal runtime mode via `-D rust_no_hxrt` (metal-only).

## 4) Architecture requirements

1. AST-first pipeline:
   - typed lowering in `RustCompiler`
   - composable pass runner (`PassRunner`)
   - deterministic printer (`RustASTPrinter`)
2. Policy analyzers:
   - profile contract analysis
   - metal island analysis
   - runtime feature inference
3. Deterministic report artifacts (opt-in):
   - `contract_report.*`
   - `runtime_plan.*`
   - `optimizer_plan.*`
   - `metal_report.*` (metal viability)

## 5) Interop policy

Preferred order:

1. Pure Haxe + std/runtime surfaces.
2. Typed `extern` + `@:native` + metadata (`@:rustCargo`, `@:rustExtraSrc`).
3. Framework-owned typed wrappers for Rust-only code.
4. Raw `__rust__` only as framework-level escape hatch.

App-side raw `__rust__` is rejected under strict mode (default in `metal`).

## 6) Quality gates

Required local/CI validation path:

1. metal policy guard: `scripts/ci/check-metal-policy.sh`
2. snapshots: `test/run-snapshots.sh`
3. upstream stdlib sweep: `test/run-upstream-stdlib-sweep.sh`
4. full harness: `npm run test:all`
5. perf tracking: `scripts/ci/perf-hxrt-overhead.sh`

## 7) Production posture

`portable` is the conservative production default for broad Haxe compatibility.

`metal` is production-viable for Rust-first teams when:

- boundary policies are enforced,
- fallback usage is measured and intentional,
- workload-specific behavior is covered by tests/benchmarks.

See:

- `docs/production-readiness.md`
- `docs/profiles.md`
- `docs/metal-profile.md`
- `docs/perf-hxrt-overhead.md`
