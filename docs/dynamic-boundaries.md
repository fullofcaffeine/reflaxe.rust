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

### File-scoped entries

- None currently.

### `std/haxe/BoundaryTypes.cross.hx` (line-scoped)

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

## Maintenance Workflow

1. Remove or type the code first.
2. Keep allowlist entries as narrow as possible.
3. If a file-scoped entry is unavoidable, add `# FILE_SCOPE_JUSTIFICATION: ...` on that line.
4. Update this document whenever allowlist entries are added, removed, widened, or narrowed.
