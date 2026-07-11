# Generated Consumer Contract

This page explains the machine-readable compatibility boundary for compiler reports, generated
Cargo crates, and the published Haxelib package. The source of truth is
[`generated-consumer-contract.json`](generated-consumer-contract.json); the public compatibility
class remains owned by [`public-compatibility-manifest.json`](public-compatibility-manifest.json).

## Why this contract exists

Successful compilation alone does not tell a report parser, build wrapper, or package consumer
which generated details it may rely on. Conversely, treating every byte of generated output as
public API would freeze rustfmt output, helper names, and implementation layout unnecessarily.

The contract therefore protects observable consumer behavior and explicitly excludes private
formatting and helper details. It is a compatibility boundary, not a promise that every candidate
has already been admitted to `1.0.0`.

## Machine-readable reports

The admitted JSON report schemas are:

| Artifact | Schema | Emission control |
| --- | --- | --- |
| `metal_report.json` | [`metal-report-v1.schema.json`](schemas/metal-report-v1.schema.json) | `rust_metal_viability_report` |
| `contract_report.json` | [`contract-report-v6.schema.json`](schemas/contract-report-v6.schema.json) | `rust_contract_report` |
| `runtime_plan.json` | [`runtime-plan-v4.schema.json`](schemas/runtime-plan-v4.schema.json) | `rust_runtime_plan_report` |
| `optimizer_plan.json` | [`optimizer-plan-v2.schema.json`](schemas/optimizer-plan-v2.schema.json) | `rust_optimizer_plan_report` |

For these files, the contract protects the filename, schema version, required field names and
types, stable identifier meanings, and explicitly listed deterministic ordering. Every object
schema permits unknown properties. Consumers of an admitted schema must ignore unknown fields;
the compiler may then add optional fields without breaking them.

A new identifier is not automatically additive when consumers may switch exhaustively. Changing
or repurposing a stable identifier, removing a required field, or changing a protected type is
incompatible. Incrementing `schemaVersion` inside the same admitted filename does not by itself
make such a replacement compatible: use a parallel versioned artifact and migration window, or a
new stable major.

The `.md` companions are human summaries. Their headings, wording, whitespace, and formatting are
not machine contracts.

## How report drift is prevented

The guard validates all four schemas with a standards-based JSON Schema implementation, validates
real compiler-emitted snapshot files, checks the compiler's filename/version/define ownership, and
cross-checks the public compatibility inventory. An immutable initial signature records the first
schema-contract baseline before its first release. The guard rejects in-place schema edits, removed
fields, changed types, removed ordering promises, and removed or silently repurposed identifiers.

The report fixture is compiled twice in the CI policy lane. All four JSON files must validate and
match byte-for-byte across the two compilations.

## Generated crate boundary

The generated-crate contract protects:

- `Cargo.toml` and `src/main.rs` root locations, Rust 2021 binary default, declared minimum
  `rust-version`, and crate-name override;
- the default `./hxrt` subtree/path dependency and proven `rust_no_hxrt` omission boundary;
- nested source paths plus documented root compatibility aliases;
- structured `@:rustCargo` merge/conflict behavior;
- consumer ownership and `{{crate_name}}` substitution for `rust_cargo_toml`;
- metadata/define-owned extra Rust source copying and module inclusion;
- documented Cargo command/flag forwarding and non-zero failure propagation;
- the four report filenames when their emission controls are enabled.

Exact whitespace, rustfmt output, temporary order, private generated helper names, internal `hxrt`
layout, and the `__hx_tests` wrapper name/layout remain private. The public `@:rustTest` metadata
contract is separate from its private generated wrapper.

## Haxelib package boundary

The release package contract protects the deterministic, safe-path Haxelib-shaped ZIP; install via
Haxelib/lix and `-lib reflaxe.rust`; staged `.cross.hx` transformation; required compiler,
`runtime/`, and `vendor/` roots; version/provenance metadata; and documented source-checkout versus
installed-package classpaths.

The release artifact tests and package smoke own those package-specific checks. The generic
generated-consumer guard links to that evidence instead of duplicating the package builder.

## Running the checks

```bash
npm run guard:generated-consumer-contract
npm run test:generated-consumer-contract
npm run test:generated-report-contract
npm run test:generated-artifact-contract
```

The first two commands are fast structural checks used by repository hooks. The report and artifact
commands compile real fixtures and run in the appropriate full CI harness lanes.
