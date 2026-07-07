# Native Facade Helper Policy

`std/rust/native/*.rs` modules are typed Rust-native facade backing code. They are not `hxrt`, and
they must not grow into a second runtime.

## Why

The compiler has two product promises that can pull in opposite directions:

- generated Rust should stay close to hand-written Rust when Haxe semantics permit it
- users should call typed Haxe APIs, not raw Rust snippets, `Dynamic` handles, or app-local generated
  Rust patches

Some Rust APIs need a small amount of Rust code because the current Haxe surface cannot declare the
real Rust shape cleanly. Examples include private fields, RAII handles, partial moves, `Drop`-sensitive
behavior, trait impl bodies, lifetimes, HRTB, const generics, macro-heavy setup, or contained unsafe
internals.

The policy is not "no handwritten Rust." The policy is "no hidden runtime drift." A helper that owns
one Rust resource behind a typed `rust.*` facade is acceptable. A helper that starts collecting broad
services, type-erased handles, generic platform abstraction, or Haxe semantic compatibility belongs
in `hxrt`, compiler lowering, or a rejected design.

## What

Every helper must be classified:

| Classification | Meaning |
| --- | --- |
| `permanent-native-facade` | Backing code for a real Rust resource/lifecycle/native wrapper that is expected to remain behind a typed facade unless a generic native-wrapper generator later replaces it. |
| `lowering-candidate` | Simple pure constructor/accessor/conversion or small wrapper that may graduate into compiler lowering once the representation is stable. |
| `experimental-scaffold` | Temporary helper accepted only with a Bead, explicit removal/graduation criteria, and review before it becomes product surface. |

Prefer compiler lowering when the operation is a pure, closed transformation from typed AST,
metadata, literals, or existing Rust primitives.

Use a native facade helper only when the operation owns or safely wraps a real Rust type/resource and
Haxe or the current compiler cannot express the required Rust shape without raw snippets, dynamic
handles, layout assumptions, or noisy generated code.

Reject helper growth when it introduces:

- `hxrt` dependency or Haxe semantic runtime behavior
- `Dynamic`, `Any`, type-erased registries, broad handles, or reflection-like dispatch
- portable `sys.*` compatibility semantics under `rust.*`
- generic platform abstraction that hides target behavior
- allocation-heavy adapters where direct Rust values are available
- catch-all `*_tools.rs` growth that collects unrelated operations

## How

For every new or expanded helper, update the closest docs, evidence, and the
[machine-checkable manifest](native-facade-manifest.json):

- Haxe owner extern/facade
- helper classification
- runtime contract (`no-hxrt` or `hxrt-bridge`)
- why compiler lowering is insufficient today
- allowed imports/dependencies
- forbidden growth
- generated call-site evidence
- no-hxrt evidence
- rustfmt/cargo evidence, and clippy where feasible
- policy or fixture coverage that proves the intended output shape
- `codeLineBudget` review threshold so helper growth is intentional

Forbidden-token checks must avoid false failures on explanatory comments. Prefer checking Cargo
dependencies, generated call expressions, helper imports, and emitted Rust code with comments
stripped or otherwise scoped to semantically relevant locations.

Run `npm run guard:native-facade-manifest` after changing `std/rust/native/*.rs`. The guard fails
when a tracked helper lacks a manifest entry, when a manifest entry points at a stale file, when real
code references imports/dependency prefixes outside the declared allowlist, when a `no-hxrt` helper
references `hxrt`, or when helper code grows beyond its review budget.

## Current Inventory

The authoritative inventory now lives in
[`docs/native-facade-manifest.json`](native-facade-manifest.json). The manifest intentionally covers
all tracked `std/rust/native/*.rs` helpers, not only the newest no-hxrt metal systems facades.

Two runtime contracts are tracked:

| Runtime contract | Meaning |
| --- | --- |
| `no-hxrt` | The helper must not reference `hxrt` and is suitable for no-runtime metal output when its owning facade and fixture also avoid `hxrt`. |
| `hxrt-bridge` | The helper intentionally bridges to existing Haxe runtime representations such as arrays, strings, iterators, maps, or generated Haxe references. This must remain explicit in the manifest and should not be used for Rust-first metal systems helpers. |

The manifest is deliberately stricter than this prose page: it lists owners, classifications,
allowed dependency prefixes, allowed imports, forbidden growth notes, evidence owners, and code-line
review budgets. New work should refine the manifest when it touches a helper, rather than expanding
unclassified behavior.

## Follow-Up Beads

| Bead | Scope |
| --- | --- |
| `haxe.rust-oo3.93` | Turn this inventory into a machine-checkable helper manifest and CI growth guard. |
| `haxe.rust-oo3.94` | Spike compiler-generated native wrapper support for simple typed Rust value wrappers. |
| `haxe.rust-oo3.95` | Revisit `rust.net.SocketAddr` as a lowering candidate once wrapper/lowering rules are stable. |
| `haxe.rust-oo3.96` | Audit resource/lifecycle helpers such as process, file, TCP, and UDP facades under this taxonomy. |
