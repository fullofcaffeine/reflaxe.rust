# HXRT Overhead Benchmarks

This benchmark tracks the overhead added by the Haxe runtime layer (`hxrt`) in generated Rust crates.

It is intentionally lightweight and CI-friendly:

- It does not fail CI on perf changes.
- It emits soft warnings when configured budgets are exceeded.
- It always publishes machine-readable artifacts.

## Why this exists

`hxrt` preserves Haxe semantics (dynamic values, exceptions, arrays, threading/runtime glue) while targeting Rust.
That semantic compatibility has a measurable footprint cost compared to pure hand-written Rust.

This benchmark keeps that cost visible over time so regressions are noticed early.

## Cases and measurements

The script benchmarks five cases:

1. `hello`:
   - `examples/hello` across `portable`, `idiomatic`, `rusty`, `metal`
   - hand-written pure Rust `println!` baseline
2. `array`:
   - `test/snapshot/for_array` across `portable`, `idiomatic`, `rusty`, `metal`
   - hand-written pure Rust array-loop baseline
3. `hot_loop`:
   - `test/perf/hot_loop` across `portable`, `idiomatic`, `rusty`, `metal`
   - hand-written pure Rust hot-loop baseline
   - startup-weighted runtime signal for a heavy workload
4. `hot_loop_inproc`:
   - `test/perf/hot_loop_inproc` across `portable`, `idiomatic`, `rusty`, `metal`
   - hand-written pure Rust in-process hot-loop baseline
   - used as the primary steady-state runtime comparison target
5. `chat`:
   - `examples/chat_loopback` via `compile.<profile>.ci.hxml` (headless deterministic mode)
   - cross-profile spread only (no pure Rust chat baseline)

For each binary:

- release binary size (`bytes`)
- stripped size (`bytes`)
- runtime average (`ms`) from either repeated process launches (`startup` mode) or in-process measurement (`inproc` mode)

## How warnings are computed

Budgets (defaults):

- size: `+5%`
- runtime: `+10%`

Comparison model:

- `hello`, `array`, `hot_loop`, and `hot_loop_inproc`: compare **ratio vs pure Rust baseline** in the same run.
- `chat`: compare **ratio vs fastest/smallest chat profile** in the same run.

Noise policy:

- `hello` / `array`: warning checks use **size ratios only** (runtime is still reported, but not warning-gated).
  Startup-only micro cases are intentionally noisy on shared CI runners.
- `hot_loop`: warning checks use **size + runtime ratios**.
  Startup-weighted heavy-workload signal (useful for trend checks).
- `hot_loop_inproc`: warning checks use **size + runtime ratios**.
  This is the primary steady-state performance signal.
  - Runtime warning gate is currently focused on `metal` (the near-pure-Rust target profile); all profile runtime ratios are still reported.
- `chat`: warning checks use profile-spread ratios (size + runtime), not pure-Rust parity.

This model keeps runtime warnings actionable while avoiding startup-noise churn.

## Profile vs pure Rust interpretation

When reading ratios (`x vs pure`):

- `portable`
  - Highest semantic compatibility / UX ergonomics.
  - Expected to carry the largest intentional runtime abstraction cost.
- `idiomatic`
  - Same semantics as portable, cleaner emitted Rust.
  - Performance envelope should stay close to portable.
- `rusty`
  - Rust-first APIs reduce semantic impedance.
  - Expected to trend closer to pure Rust in hot-path workloads.
- `metal` (experimental)
  - Lowest-level typed Rust interop profile.
  - Primary target profile for near-pure-Rust performance.

## What the current baseline shows

The committed baseline (`scripts/ci/perf/hxrt-baseline.json`) currently shows:

- Binary footprint is dominated by shared runtime payload across profiles in micro cases (roughly the same multiplier for `portable`/`idiomatic`/`rusty`/`metal`).
- Startup-only microcases (`hello`, `array`) fluctuate and are tracked mainly for size/regression visibility.
- Steady-state `hot_loop_inproc` runtime ratios are the main signal for parity work.

Interpretation:

- The runtime crate (`hxrt`) is still the largest fixed overhead source.
- Profile-level runtime differences mostly come from emitted API style and boundary/abstraction usage, not from fundamentally different runtime payloads.
- Closing the `metal` hot-loop gap is an explicit optimization objective, not an accidental drift.

## Performance targets policy

Directionally, this project targets production-grade competitiveness with pure Rust.

Current policy:

1. `metal` is the primary performance profile.
   - Stretch target for steady-state workloads (`hot_loop_inproc` runtime ratio): `<= 1.05x` vs pure Rust.
   - Long-term target: approach `1.00x` where semantics permit.
   - If current measurements are above this target, treat that as active optimization backlog (not a reason to relax the target).
2. `portable` accepts a larger tradeoff in exchange for Haxe UX and semantic portability.
   - Runtime/size deltas are explicitly tracked and should not regress without intent.
3. Any runtime abstraction cost that can be removed without semantic break should be treated as optimization backlog.

These are guiding targets, not hard CI fail gates yet.

## Commands

Run benchmark (compare mode):

```bash
npm run test:perf:hxrt
```

Regenerate baseline file:

```bash
npm run test:perf:hxrt:update-baseline
```

Baseline file:

- `scripts/ci/perf/hxrt-baseline.json`

## CI integration

CI runs `scripts/ci/perf-hxrt-overhead.sh` on PRs and `main`.

Outputs are emitted in all three places:

1. GitHub log warnings (`::warning::`)
2. step summary (`$GITHUB_STEP_SUMMARY`)
3. artifact files under `.cache/perf-hxrt/results`

Primary files:

- `current.json` (full current run)
- `comparison.json` (warning decisions)
- `raw_metrics.tsv` (flat metrics table)
- `summary.md` (human-readable report, including metal target tracking status for `hot_loop_inproc`)

## Updating the baseline safely

1. Run `npm run test:perf:hxrt:update-baseline`.
2. Run `npm run test:perf:hxrt` once to confirm compare mode is stable.
3. Commit `scripts/ci/perf/hxrt-baseline.json` with an explanation in the commit message.

Only update the baseline when you intentionally change runtime/perf expectations, not to hide regressions.
