# Rust-to-Haxe source maps

Every generated crate now contains `rust-source-map.json`. It records where compiler-emitted Rust
bytes came from without changing the Rust source itself.

## Why this exists

Rust remains the final authority for ownership, lifetimes, trait rules, and external crates. When
rustc reports an error, however, its span points into generated `.rs` code. A useful Haxe-facing
diagnostic needs an honest way to answer one of two things:

- “these Rust bytes came from this exact Haxe source position”; or
- “the compiler created these bytes for this explicit reason.”

Guessing from a basename or a nearby line is unsafe. Two generated files can share a name, and a
formatter can move every later byte. The source-map lookup therefore fails closed instead of making
a plausible but wrong attribution.

## What the artifact contains

The version-1 shape is documented by
[`rust-source-map-v1.schema.json`](schemas/rust-source-map-v1.schema.json). At the top level it has:

- `schemaVersion`: currently `1`;
- `generator`: `reflaxe.rust`;
- `files`: generated Rust files sorted by their complete crate-relative filename.

Each file entry records its UTF-8 byte length, line count, SHA-256 content hash, and sorted mapping
ranges. A mapping contains:

- the structural node kind: `item`, `statement`, or `expression`;
- an `originDepth` used to prefer the inner, more specific origin when two wrappers print the same
  byte range;
- a half-open generated UTF-8 byte range plus one-based line and UTF-8 byte-column coordinates;
- either an exact Haxe byte/line range or a closed compiler-generated reason.

The generated-reason list has one machine-readable owner:
[`rust-source-map-policy.json`](../rust-source-map-policy.json). Run
`npm run docs:sync:rust-source-map-policy` after changing it. That generator updates both the Haxe
enum/decoder and the JSON Schema enum; `npm run guard:rust-source-map-policy` rejects either consumer
when it is stale.

Source filenames are repository-relative when they belong to the project. Sources resolved from a
known Haxe classpath use a `classpath/…` identity. Absolute paths and `.` / `..` path components are
rejected, so the artifact does not expose a checkout location and remains repeatable across clean
checkouts.

## How lookup stays exact

The typed internal consumer in `reflaxe.rust.RustSourceMap` requires all three inputs:

1. the complete crate-relative generated filename;
2. rustc's half-open UTF-8 byte span;
3. the complete current generated file content.

Lookup first verifies the content length and SHA-256. It rebuilds a byte index from those exact
bytes and rejects the complete file if its recorded line count or any mapping endpoint disagrees
with the byte-derived line and column. It then chooses the smallest containing generated range, the
most specific structural node kind, and finally the deepest origin wrapper. It never falls back to
a basename and never uses a changed file's old line numbers.

Files emitted from multiple Haxe types are aggregated with the same `\n\n` separator and in the
same order as Reflaxe's file-per-module writer. Mapping-aware printing is also contract-tested to
produce byte-for-byte the same Rust as ordinary printing.

Aggregation stores chunks plus a running UTF-8 byte length. It shifts each chunk's mappings once
and joins the text once, avoiding repeated rescans and copies of the complete accumulated module.

## Formatting boundary

The map describes the bytes emitted by the compiler. Running `cargo fmt`, enabling `-D rustfmt`, or
editing a generated `.rs` file changes those bytes. The old map then remains readable but exact
lookup returns no result because its hash no longer matches.

For source-mapped diagnostic work, consume rustc JSON against the unformatted compiler output or
regenerate the crate after any edit. This fail-closed boundary is intentional; version 1 does not
attempt to guess how rustfmt moved a span.

## Current scope

This artifact and its exact typed lookup are the provenance foundation. Existing Haxe compiler
diagnostics continue to use their normal Haxe positions. General Cargo/rustc JSON presentation—such
as rewriting every residual borrow-checker message into a friendly Haxe diagnostic—is separate
follow-up work under the borrow-provenance roadmap. Until that integration lands,
`rust-source-map.json` is primarily an internal diagnostic bridge rather than a promise that every
rustc message is already shown at a Haxe expression automatically.

The focused contract is:

```bash
npm run test:rust-source-map
```

It runs the production transformer pipeline, mutation tests for unsafe paths, stale content, and
dishonest UTF-8 coordinates, two byte-identical compilations, schema-policy parity, no-`hxrt`
wrapper traversal, 1,000/10,000-chunk aggregation checks, rustc-backed mutable-guard inference,
and a warning-clean Cargo build plus runtime behavior checks.
