# Dynamic Boundaries

This document is the source of truth for intentional `Dynamic` usage in `reflaxe.rust`.

## Policy

- Default rule: do not use `Dynamic`.
- Allowlist rule: prefer exact `path:line` entries in `scripts/lint/dynamic_allowlist.txt`.
- Exception rule: any future file-scoped allowlist entry is temporary and must include
  `# FILE_SCOPE_JUSTIFICATION: ...` inline in the allowlist.

## Current Allowlist

### `src/reflaxe/rust/DynamicBoundary.hx` (line-scoped)

- Why: this module is the intentional single source of truth for the unavoidable `Dynamic` type-name
  literal used by compiler/analyzer boundary logic.
- Current narrowing:
  - compiler lowering and analyzers route dynamic-boundary naming/path decisions through
    `DynamicBoundary.typeName()` and `DynamicBoundary.runtimeNamespace()`.
  - avoids scattered diagnostics/comparison literals across files, keeping allowlist churn minimal.
- Guardrail: unresolved monomorph and unmapped `@:coreType` fallback now errors in user/project code
  by default (fallback remains only for framework/upstream std compatibility).
- Status: line-scoped entries are generated from non-comment `Dynamic` usage lines
  (comment-only/doc-text mentions are ignored by the guard).
- Exit criteria: remove this entry only if upstream/runtime contracts no longer require a dynamic
  carrier type name literal.

### `src/reflaxe/rust/RustCompiler.hx` family std pin report parser (line-scoped)

- Why: `buildFamilyStdPinReportSnapshot()` records `family/family_std_pin.json` metadata in compiler
  report artifacts. Haxe's `haxe.Json.parse` API returns `Dynamic`, so the parser must cross a small
  JSON boundary before narrowing to `FamilyStdPinReportSnapshot`.
- Current narrowing:
  - parse only inside `buildFamilyStdPinReportSnapshot()`;
  - immediately project the allowed fields (`name`, `version`, `source`, `migration_window.mode`);
  - store only strings and a boolean in the typed report snapshot;
  - keep missing or malformed JSON non-fatal and deterministic.
- Guardrail: app/compiler logic outside this parser must consume the typed `FamilyStdPinReportSnapshot`,
  not the parsed dynamic object.
- Exit criteria: replace this boundary with a typed JSON decoder or generated codec that can parse
  the pin schema without raw `Dynamic`.

### `src/reflaxe/rust/RustSourceMap.hx` source-map decoder (line-scoped)

- Why: `haxe.Json.parse` necessarily returns one untyped value before an internal diagnostic
  consumer can validate `rust-source-map.json`.
- Current narrowing:
  - one documented `RustSourceMapJsonValue` alias owns the parser result;
  - object, array, string, and integer helpers validate every field immediately;
  - only typed source-map documents, files, mappings, origins, and spans reach lookup logic.
- Guardrail: path safety, the closed generated-reason vocabulary, deterministic mapping order, and
  content hashes are revalidated after parsing; no untyped value escapes the codec section.
- Exit criteria: replace the alias if Haxe gains a typed JSON decoder that can construct the
  versioned source-map schema without an untyped parser result.

### Representation planning and runtime reporting (line-scoped)

- Why: the compiler must recognize the Haxe `Dynamic` type and explain when a concrete value, such
  as an `Int` or enum value, is placed into that runtime container.
- Current narrowing:
  - the type analyzer has one exact comparison for the built-in Haxe type;
  - the runtime report has a small set of user-facing messages and path checks for this one runtime
    boundary;
  - complete typed-module analysis saves the exact conversion action before generating Rust;
  - Rust lowering must consume that saved action exactly once, and compilation stops if an action is
    missing, duplicated, malformed, or left unused;
  - an immutable `rust.Ref<T>` crossing records whether lowering must copy or clone the owned `T`, so
    the short-lived borrow itself is never placed into the runtime container.
- Guardrail: these entries describe or recognize the unavoidable boundary. They do not permit
  untyped values to spread through compiler logic.
- Exit criteria: remove an entry only when the same behavior can be expressed through a stronger
  typed Haxe API without losing compatibility.

### File-scoped entries

- None currently.

### `std/rust/_std/haxe/BoundaryTypes.hx` (line-scoped)

- Why: this module is the intentional stdlib boundary alias hub for unavoidable untyped payload contracts.
- Lines allowlisted:
  - `ConstraintValue`
  - `JsonValue`
  - `SysPrintBoundaryValue`
  - `SocketCustomBoundaryValue`
  - `ThreadMessageBoundaryValue`
  - `SqlBoundaryValue`
  - `DbResultRowBoundaryValue`
  - `StringBufAddBoundaryValue`
  - `ExceptionBoundaryValue`
- Exit criteria: upstream API contract changes that remove these untyped boundaries.

### Snapshot fixtures (line-scoped)

- `test/snapshot/catch_dynamic/Main.hx:6`
- `test/snapshot/throw_tail_nonvoid/Main.hx:12`

Why:
- These are intentional regression fixtures that validate catch-all dynamic behavior remains compatible.

Exit criteria:
- If target semantics intentionally change and the fixtures are replaced with typed behavior.

### Representation boundary fixtures (line-scoped)

- Why: these focused compiler tests deliberately place concrete values into `Dynamic` parameters,
  locals, returns, enum payloads, constructor arguments, and scoped immutable borrows. They prove
  that the compiler reports the exact crossing before Rust generation, consumes the saved action,
  and does not overlook framework-owned signatures or constructor bodies.
- Guardrail: only the individual declarations and expressions needed to exercise the boundary are
  allowlisted. The test assertions use ordinary-language descriptions rather than adding extra
  allowlist entries for message text.
- Exit criteria: remove these entries if Haxe replaces the tested upstream `Dynamic` contracts with
  concrete typed APIs.

## Maintenance Workflow

1. Remove or type the code first.
2. Keep allowlist entries as narrow as possible.
3. If a file-scoped entry is unavoidable, add `# FILE_SCOPE_JUSTIFICATION: ...` on that line.
4. Update this document whenever allowlist entries are added, removed, widened, or narrowed.
