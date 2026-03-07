# `.cross.hx`, `_std`, and Family Hardening Notes

This document records how `reflaxe.rust` currently uses `.cross.hx`, what that means for sibling coexistence, and where hardening still makes sense.

## Current model in this repo

`reflaxe.rust` uses `std/**/*.cross.hx` as its main stdlib override model.

This repo does **not** currently have an early `src/haxe/*.cross.hx` set.

Bootstrap activation is also relatively narrow:

- `target.name == "rust"`
- or `-D rust_output=...`

That is an important difference from broader Haxe 4 `Cross` activation patterns.

## Quick matrix

| Question | Answer for this repo |
| --- | --- |
| Main override style | `std/**/*.cross.hx` as the main override model |
| Is `_std` used? | not as the dominant public override layer |
| Is `.cross.hx` used broadly? | yes |
| Does this repo own early `src/haxe/*` modules? | no |
| Bootstrap activation currently keys off raw Haxe 4 `Cross`? | no |
| Same-compilation sibling-target coexistence safe today? | not guaranteed |
| Highest-priority hardening item | add mixed-target fail-fast while preserving narrow target activation |

## What `.cross.hx` means here

In this repo, `.cross.hx` is the normal packaged target-override model.

It is not mainly an early-bootstrap exception mechanism.

That is also how this repo's stdlib policy frames it:

- upstream-colliding std overrides live under `std/**`
- `.cross.hx` keeps them target-conditional and reduces leakage into non-target contexts

## What `_std` means here

`_std` is not the dominant override lane in this repo.

The current design is simpler than OCaml's split:

- most override ownership lives directly in `std/**/*.cross.hx`
- bootstrap activates that stdlib only for real Rust builds

That is a valid design, but it means sibling coexistence depends on keeping activation narrow and ownership collisions visible.

## Current coexistence risk

This repo does not have the same early `src/haxe/*` collision profile as OCaml and Elixir.

That lowers the risk.

But it still shares many module names with sibling targets, including:

- `StringTools`
- `Date`
- `Lambda`
- `Sys`
- `haxe.Exception`
- `haxe.CallStack`
- `haxe.Constraints`

The most important one is `haxe.Exception`.

Rust owns that module under `std/haxe/Exception.cross.hx`, while OCaml and Elixir currently own early `src/haxe/Exception.cross.hx` files.

If a sibling early file wins resolution first in a mixed-target compile, Rust can lose the real implementation it expected.

## Risk level

Current status:

- default one-target-at-a-time use: acceptable
- same-compilation multi-target coexistence: still risky enough to deserve hardening

This repo is not the highest-risk member of the family, but it should not rely on classpath order if mixed activation becomes more common.

## Hardening direction

Recommended next steps:

1. Keep bootstrap activation narrow and target-specific.
2. Add explicit mixed-target detection/fail-fast behavior when conflicting sibling target libraries are active.
3. Document `haxe.Exception` ownership as a family collision surface that should not silently resolve by classpath luck.

## Local sibling references

Workspace-local companion docs:

- `../haxe.ocaml/docs/02-user-guide/CROSS_AND_STAGED_STDLIB_GUIDE.md`
- `../haxe.ocaml/docs/00-project/REFLAXE_FAMILY_CROSS_OVERRIDE_AUDIT.md`
- `../haxe.elixir.codex/docs/05-architecture/CROSS_OVERRIDES_AND_MULTI_TARGET_HARDENING.md`
- `../haxe.go/docs/cross-overrides-and-hardening.md`

These sibling-relative paths are intended for local multi-repo work, not for a single published docs site.

## Absolute-path protection

This repo already has staged local-path leak protection in pre-commit via:

- `scripts/hooks/pre-commit`
- `scripts/lint/local_path_guard_staged.sh`

So the remaining hardening work here is target-activation clarity, not path-leak hook absence.
