# Oracle Review: M42 Scoped Borrow Region Model

This is the paste-ready external Oracle/GPT-5.5 Pro review prompt for
`haxe.rust-oo3.74.2`.

## Review Result

Oracle verdict: `APPROVE_WITH_CHANGES`.

Accepted direction:

- scoped callback borrow regions are a coherent Haxe encoding for a useful Rust-lifetime subset,
- the macro guard is a reasonable first-pass non-escape check,
- a full typed-AST borrow checker is not required for this Bead closure,
- the docs correctly avoid claiming full Rust lifetime parity.

Required changes before closure:

- Narrow returned array/object literal detection so owned derivations such as `VecTools.len(r)` are
  allowed inside returned literals.
- Add `rust.Str` spawned-boundary coverage in `SendSyncAnalyzer`, or explicitly record it as a
  follow-up.
- Add compact escape-shape fixtures for return token, outer assignment, returned literal, and
  returned closure capture.
- Track typed alias/storage, wrapper/constructor/throw escape, overlapping mutable-region,
  no-clone slice-view, and RAII/lifetime-island follow-ups in Beads.

These changes landed before `haxe.rust-oo3.74.2` closed. The prompt below is the original review
request. The review result above supersedes any fixture names or wording that Oracle asked us to
change.

## Uploads

Upload this current repo bundle:

- `repomix-output.haxe-rust-m42-borrow-region-20260703.xml.zip`

Notes:

- The bundle should be generated after the borrow-region changes in this worktree.
- The review does not need the older `repomix-output.haxe-rust.xml.zip` or
  `repomix-output.haxe-rust-m42-capability-20260703.xml.zip`.
- The sibling `../codex-hxrust` app does not need to be uploaded unless the reviewer asks about
  killer-app QA details. For this change, its generated Cargo smoke passed in both portable and
  metal modes.

## Files To Inspect

Ask Oracle to prioritize these files in the uploaded bundle:

- `AGENTS.md`
- `docs/lifetime-encoding.md`
- `docs/metal-haxified-rust-roadmap.md`
- `docs/metal-capability-fixtures.md`
- `docs/metal-type-surface-gap-matrix.md`
- `docs/metal-profile.md`
- `docs/profiles.md`
- `std/rust/Borrow.hx`
- `std/rust/SliceTools.hx`
- `std/rust/MutSliceTools.hx`
- `std/rust/StrTools.hx`
- `std/rust/Ref.hx`
- `std/rust/MutRef.hx`
- `std/rust/Slice.hx`
- `std/rust/MutSlice.hx`
- `src/reflaxe/rust/macros/BorrowRegionMacroGuard.hx`
- `src/reflaxe/rust/analyze/SendSyncAnalyzer.hx`
- `scripts/ci/check-metal-policy.sh`
- `test/negative/metal_ref_escape/Main.hx`
- `test/negative/metal_mut_ref_escape/Main.hx`
- `test/negative/metal_slice_escape/Main.hx`
- `test/negative/metal_mut_slice_escape/Main.hx`
- `test/negative/send_sync_borrow_capture/Main.hx`
- `test/snapshot/rust_borrow_ref/Main.hx`
- `test/snapshot/rust_borrow_mut/Main.hx`
- `test/snapshot/rust_array_slice_views/Main.hx`
- `test/snapshot/rust_str_slice/Main.hx`
- `test/snapshot/borrow_scope_tightening/Main.hx`
- `.beads/issues.jsonl` entry for `haxe.rust-oo3.74.2`

## Original Prompt

You are reviewing the Haxe-to-Rust target `reflaxe.rust`.

This is a second-pass architecture and implementation review for Bead `haxe.rust-oo3.74.2`,
part of Milestone 42: "Metal as haxified Rust".

The repo goal is to make Haxe-authored Rust production-grade:

- generated Rust should be readable, idiomatic, rustfmt-friendly, warning-clean, and close to
  hand-written Rust where Haxe semantics permit;
- `portable` remains the default Haxe-semantics contract;
- `metal` is the explicit Rust-first authoring contract;
- Rust-native authority should be exposed through typed Haxe surfaces, metadata, macros, and extern
  islands rather than app-side raw Rust snippets;
- `hxrt` should be lightweight and used only where semantics require runtime support.

The specific design under review:

Haxe cannot express Rust lifetimes directly. The current plan treats scoped helper callbacks as
lexical borrow regions:

- `rust.Borrow.withRef(value, r -> body)` creates `r: rust.Ref<T>` for the callback body.
- `rust.Borrow.withMut(value, r -> body)` creates `r: rust.MutRef<T>`.
- `rust.SliceTools.with(value, s -> body)` creates `s: rust.Slice<T>`.
- `rust.MutSliceTools.with(value, s -> body)` creates `s: rust.MutSlice<T>`.
- `rust.StrTools.with(value, s -> body)` creates `s: rust.Str`.

The implementation now adds `BorrowRegionMacroGuard`, a first-pass syntax-level guard used by these
scoped helper macros before Rust code is emitted. It rejects direct escapes of the callback token:

- callback tail expression is the token, for example `Borrow.withRef(v, r -> r)`;
- `return token`;
- assignment of the token to another slot, for example `escaped = r`;
- returned array/object literals that directly contain the token;
- returned closures that capture the token.

It intentionally does not claim to be a full borrow checker. It still allows ordinary owned
derivations such as `Borrow.withRef(v, r -> VecTools.len(r))`. It also intentionally does not scan
arbitrary nested callback bodies as escapes, because existing nested scoped helper patterns such as
`Borrow.withRef(key, k -> Borrow.withMut(map, m -> insert(m, k, value)))` should remain valid. Spawn
boundaries are handled by the existing typed `SendSyncAnalyzer`, which rejects borrow-token captures
in thread/task spawn closures under the strict Send/Sync policy.

The docs now frame this as:

- current baseline: callback-scoped lexical regions plus first-pass macro guards;
- future typed-pass work: alias-sensitive tracking for field/static storage, alias returns, unknown
  closure escape, and conflicting mutable borrow regions;
- phantom region types remain a candidate only if they improve diagnostics without hurting Haxe
  ergonomics;
- lifetime-heavy generic Rust APIs should stay behind typed extern/facade islands.

New fixture evidence:

- `test/negative/metal_ref_escape`
- `test/negative/metal_mut_ref_escape`
- `test/negative/metal_slice_escape`
- `test/negative/metal_mut_slice_escape`
- existing `test/negative/send_sync_borrow_capture`

Validation already run locally:

- full `scripts/ci/check-metal-policy.sh`;
- focused snapshots: `rust_borrow_ref`, `rust_borrow_mut`, `rust_array_slice_views`,
  `rust_str_slice`, `borrow_scope_tightening`;
- `npm run docs:check:navigation`;
- `npm run docs:check:progress`;
- `npm run guard:local-paths`;
- `git diff --check`;
- `npm run test:codex-hxrust`.

Please review whether this is sound enough for the current Bead and whether it preserves the
long-term metal model.

Focus questions:

1. Is the scoped callback model a coherent Haxe encoding for a useful subset of Rust lifetimes?
2. Is `BorrowRegionMacroGuard` a reasonable first-pass static non-escape check before Rust compile,
   or is a typed-AST pass required before this Bead can close?
3. Are the rejected direct escape shapes the right first wave?
4. Is the decision to skip arbitrary nested callback bodies sound, given valid nested borrow-helper
   patterns and the existing `SendSyncAnalyzer` spawn-boundary check?
5. Are there Haxe macro AST edge cases in `BorrowRegionMacroGuard` that could cause false positives,
   false negatives, or confusing diagnostics?
6. Do the docs clearly distinguish current enforcement from future alias/conflict tracking and avoid
   overpromising Rust lifetime parity?
7. Are phantom-region types evaluated fairly, or should they be moved earlier/later in the plan?
8. Are the new negative fixtures sufficient for the Bead acceptance criteria, alongside the existing
   spawned borrow-capture fixture?
9. What additional typed-pass or fixture follow-ups should be added to Beads before broader metal
   lifetime/RAII work?
10. Should `haxe.rust-oo3.74.2` close after this implementation plus docs and validation, or remain
    open until alias-sensitive typed-region tracking lands?

Please return:

- verdict: `APPROVE`, `APPROVE_WITH_CHANGES`, or `BLOCK`;
- top findings ordered by severity;
- concrete code/doc/fixture changes to make before closure;
- recommended follow-up Beads tasks, if any;
- a short final note suitable to paste into the `haxe.rust-oo3.74.2` Beads comment.
