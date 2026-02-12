# Compiler Progress Tracker (toward 1.0)

Last updated: 2026-02-12

This is the non-expert view of where `reflaxe.rust` stands for production use.
It maps directly to Beads issues so status is auditable and not hand-wavy.

## Executive summary

- Core compiler roadmap epic (`haxe.rust-oo3`) is complete.
- 1.0 parity epic (`haxe.rust-4jb`) is still open because one P0 blocker is in progress and one docs task is open.
- Advanced TUI harness epic (`haxe.rust-cu0`) is mostly complete; animation/effects work remains open.

## Progress at a glance

Use this as a planning signal, not an SLA.

- **Foundation compiler milestones**: complete (`haxe.rust-oo3`)
- **v1.0 stdlib/sys parity**: mostly complete, blocked by `haxe.rust-f63` (String nullability representation)
- **Docs and onboarding quality**: in progress (`haxe.rust-cfh`)
- **Battle-test example harness**: mostly complete (`haxe.rust-cu0`), polish still open (`haxe.rust-vrd`)

## Live workstreams (direct Beads mapping)

### 1) P0 release blocker: String nullability

- Issue: `haxe.rust-f63` (in progress)
- Why it matters: Haxe `String` is nullable by default; Rust `String` is not.
- Current state: nullable representation exists in runtime (`HxString`), but switching all typed call paths is incomplete and causes broad type mismatches.
- Exit condition:
  - `var s:String = null; Sys.println(s);` behaves correctly,
  - string concat with null matches Haxe semantics,
  - snapshots/examples remain green.

### 2) P1 docs parity task

- Issue: `haxe.rust-cfh` (open)
- Why it matters: docs currently mix old/new runtime assumptions and are hard for non-compiler users.
- Exit condition:
  - docs reflect current runtime/emission model,
  - profile behavior and known limitations are explicit and consistent,
  - onboarding path is clear for both Haxe-first and Rust-first teams.

### 3) Advanced TUI harness as production stress-test

- Epic: `haxe.rust-cu0` (open, most children complete)
- Open child: `haxe.rust-vrd` (animations/effects)
- Why it matters: this app is the “real app” harness that catches compiler/runtime edge cases and verifies profile behavior under richer UI state/event flows.

## 1.0 exit criteria (plain language)

We should only call the compiler 1.0 production-ready when all of the following are true:

1. `haxe.rust-4jb` is closed.
2. No P0/P1 readiness blockers remain open in Beads.
3. `npm run test:all` is green locally and in CI on push/PR.
4. Example matrix compiles/runs across portable + rusty variants (including `examples/tui_todo` harness checks).
5. Public docs match real behavior (profiles, runtime semantics, interop rules, known limitations).

## How to check status yourself

```bash
bd graph haxe.rust-4jb --compact
bd ready
npm run test:all
```

If these disagree with this doc, trust Beads/CI first and update this file.
