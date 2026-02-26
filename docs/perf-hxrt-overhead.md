# HXRT Overhead Benchmarks

This benchmark tracks the overhead added by the Haxe runtime layer (`hxrt`) in generated Rust crates.

It is intentionally lightweight and CI-friendly:

- It supports gate modes: `soft`, `pr`, `nightly`.
- `soft` emits warnings only.
- `pr` enforces coarse hard-fail thresholds for major regressions.
- `nightly` enforces tighter hard-fail thresholds.
- It always publishes machine-readable artifacts.

## Why this exists

`hxrt` preserves Haxe semantics (dynamic values, exceptions, arrays, threading/runtime glue) while targeting Rust.
That semantic compatibility has a measurable footprint cost compared to pure hand-written Rust.

This benchmark keeps that cost visible over time so regressions are noticed early.

## Cases and measurements

The script benchmarks six cases:

1. `hello`:
   - `examples/hello` across `portable`, `metal`
   - hand-written pure Rust `println!` baseline
2. `array`:
   - `test/snapshot/for_array` across `portable`, `metal`
   - hand-written pure Rust array-loop baseline
3. `hot_loop`:
   - `test/perf/hot_loop` across `portable`, `metal`
   - hand-written pure Rust hot-loop baseline
   - startup-weighted runtime signal for a heavy workload
4. `hot_loop_inproc`:
   - `test/perf/hot_loop_inproc` across `portable`, `metal`
   - hand-written pure Rust in-process hot-loop baseline
   - used as the primary steady-state runtime comparison target
5. `hot_loop_no_hxrt`:
   - `test/perf/hot_loop_no_hxrt` in `metal` with `-D rust_no_hxrt`
   - hand-written pure Rust in-process hot-loop baseline
   - verifies the no-runtime metal path stays close to pure Rust
6. `chat`:
   - `examples/chat_loopback` via `compile.<profile>.ci.hxml` (headless deterministic mode)
   - cross-profile spread only (no pure Rust chat baseline)

For each binary:

- release binary size (`bytes`)
- stripped size (`bytes`)
- runtime metric (`ms`) by mode:
  - `startup`: arithmetic mean over repeated process launches
  - `inproc`: median over per-run samples, plus dispersion via MAD (median absolute deviation)

## Benchmark protocol

Runtime measurement protocol is fixed so pass/fail decisions are explainable and repeatable:

- `startup` mode (`hello`, `array`, `hot_loop`, `chat`)
  - process is launched repeatedly with `/usr/bin/time`
  - reported runtime metric is `mean_ms`
- `inproc` mode (`hot_loop_inproc`, `hot_loop_no_hxrt`)
  - each run is timed independently
  - reported runtime metric is `median_ms`
  - dispersion is reported as `mad_ms`
- run counts are explicit and configurable:
  - `HXRT_PERF_HELLO_ITERS`
  - `HXRT_PERF_ARRAY_ITERS`
  - `HXRT_PERF_HOT_LOOP_ITERS`
  - `HXRT_PERF_HOT_LOOP_INPROC_RUNS`
  - `HXRT_PERF_HOT_LOOP_NO_HXRT_INPROC_RUNS`
  - `HXRT_PERF_CHAT_ITERS`

Artifacts include protocol + runtime stats used in decisions:

- `current.json` includes `protocol` and `runtimeStats`
- `summary.md` includes an in-process runtime stats section (mean/median/MAD + sample count)
- `comparison.json` includes warning/hard-gate decisions

## Gate modes and hard thresholds

Use explicit gate mode:

```bash
bash scripts/ci/perf-hxrt-overhead.sh --gate-mode <soft|pr|nightly>
```

Modes:

- `soft` (default): warnings only.
- `pr`: coarse hard-fail thresholds (noise-tolerant major-regression guard).
- `nightly`: tighter hard-fail thresholds.

Default hard-fail thresholds:

- `pr`
  - size regression vs baseline: `+20%`
  - runtime regression vs baseline: `+25%`
  - portable/metal convergence caps:
    - `array` runtime `<= 1.20x`
    - `hot_loop_inproc` runtime `<= 1.10x`
- `nightly`
  - size regression vs baseline: `+8%`
  - runtime regression vs baseline: `+15%`
  - portable/metal convergence caps:
    - `array` runtime `<= 1.08x`
    - `hot_loop_inproc` runtime `<= 1.08x`

Environment overrides:

- `HXRT_PERF_GATE_MODE`
- `HXRT_PERF_PR_SIZE_FAIL_PCT`
- `HXRT_PERF_PR_RUNTIME_FAIL_PCT`
- `HXRT_PERF_PR_PORTABLE_METAL_ARRAY_MAX`
- `HXRT_PERF_PR_PORTABLE_METAL_HOT_LOOP_INPROC_MAX`
- `HXRT_PERF_NIGHTLY_SIZE_FAIL_PCT`
- `HXRT_PERF_NIGHTLY_RUNTIME_FAIL_PCT`
- `HXRT_PERF_NIGHTLY_PORTABLE_METAL_ARRAY_MAX`
- `HXRT_PERF_NIGHTLY_PORTABLE_METAL_HOT_LOOP_INPROC_MAX`

## How warnings are computed

Budgets (defaults):

- size: `+5%`
- runtime: `+10%`
- portable vs metal convergence:
  - `array` runtime portable/metal must stay `<= 1.08x`
  - `hot_loop_inproc` runtime portable/metal must stay `<= 1.05x`

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
- `hot_loop_no_hxrt`: warning checks use **size + runtime ratios**.
  - Runtime warning gate is focused on `metal` (no-hxrt mode only).
- `chat`: warning checks use profile-spread ratios (size + runtime), not pure-Rust parity.

This model keeps runtime warnings actionable while avoiding startup-noise churn.

Additional explicit convergence checks:

- `portable_vs_metal.arrayRuntimePortableVsMetal`
- `portable_vs_metal.hotLoopInprocRuntimePortableVsMetal`

These checks are emitted in `comparison.json` and `summary.md`, and they warn when
portable drifts too far from metal on the two primary convergence workloads.

## Profile vs pure Rust interpretation

When reading ratios (`x vs pure`):

- `portable`
  - Highest semantic compatibility / UX ergonomics.
  - Expected to carry the largest intentional runtime abstraction cost.
- `metal`
  - Rust-first performance profile.
  - Primary target profile for near-pure-Rust performance.
- `metal + rust_no_hxrt`
  - No-runtime constrained subset used as the lower-bound parity signal.
  - Tracks how close generated Rust can get when portable runtime semantics are intentionally excluded.

## What the current baseline shows

The committed baseline (`scripts/ci/perf/hxrt-baseline.json`) currently shows:

- Binary footprint is dominated by shared runtime payload across profiles in micro cases (roughly the same multiplier for `portable`/`metal`).
- Startup-only microcases (`hello`, `array`) fluctuate and are tracked mainly for size/regression visibility.
- Steady-state `hot_loop_inproc` runtime ratios are the main signal for parity work.
- `hot_loop_no_hxrt` provides a no-runtime lower-bound signal for metal parity.

Interpretation:

- The runtime crate (`hxrt`) is still the largest fixed overhead source.
- Profile-level runtime differences mostly come from emitted API style and boundary/abstraction usage, not from fundamentally different runtime payloads.
- Closing the `metal` hot-loop gap is an explicit optimization objective, not an accidental drift.
- `metal + rust_no_hxrt` is tracked separately so runtime-free improvements are visible and regressions are caught.

## Performance targets policy

Directionally, this project targets production-grade competitiveness with pure Rust.

Current policy:

1. `metal` is the primary performance profile.
   - Stretch target for steady-state workloads (`hot_loop_inproc` runtime ratio): `<= 1.05x` vs pure Rust.
   - Long-term target: approach `1.00x` where semantics permit.
   - If current measurements are above this target, treat that as active optimization backlog (not a reason to relax the target).
   - `metal + rust_no_hxrt` should stay at or better than regular `metal` for the same workload.
2. `portable` accepts a larger tradeoff in exchange for Haxe UX and semantic portability.
   - Runtime/size deltas are explicitly tracked and should not regress without intent.
3. Any runtime abstraction cost that can be removed without semantic break should be treated as optimization backlog.

These are strategic targets; CI gate mode determines whether a given run enforces hard failures (`pr`/`nightly`) or warnings-only (`soft`).

## Commands

Run benchmark (compare mode):

```bash
npm run test:perf:hxrt
```

Run benchmark with explicit hard-gate modes:

```bash
HXRT_PERF_HOT_LOOP_INPROC_RUNS=60 HXRT_PERF_HOT_LOOP_NO_HXRT_INPROC_RUNS=60 bash scripts/ci/perf-hxrt-overhead.sh --gate-mode pr
HXRT_PERF_HOT_LOOP_INPROC_RUNS=60 HXRT_PERF_HOT_LOOP_NO_HXRT_INPROC_RUNS=60 bash scripts/ci/perf-hxrt-overhead.sh --gate-mode nightly
```

Regenerate baseline file:

```bash
npm run test:perf:hxrt:update-baseline
```

Baseline file:

- `scripts/ci/perf/hxrt-baseline.json`

Optional convergence budget overrides:

- `HXRT_PERF_PORTABLE_METAL_ARRAY_MAX` (default `1.08`)
- `HXRT_PERF_PORTABLE_METAL_HOT_LOOP_INPROC_MAX` (default `1.05`)

Hard-gate override families:

- PR gate: `HXRT_PERF_PR_*`
- nightly gate: `HXRT_PERF_NIGHTLY_*`

## CI integration

Current workflow wiring:

- PR/main CI (`.github/workflows/ci.yml`):
  - `HXRT_PERF_HOT_LOOP_INPROC_RUNS=60 HXRT_PERF_HOT_LOOP_NO_HXRT_INPROC_RUNS=60 bash scripts/ci/perf-hxrt-overhead.sh --gate-mode pr`
- Weekly evidence (`.github/workflows/weekly-ci-evidence.yml`):
  - `HXRT_PERF_GATE_MODE=nightly HXRT_PERF_HOT_LOOP_INPROC_RUNS=60 HXRT_PERF_HOT_LOOP_NO_HXRT_INPROC_RUNS=60 bash scripts/ci/local.sh`

Outputs are emitted in all three places:

1. GitHub log warnings (`::warning::`)
2. step summary (`$GITHUB_STEP_SUMMARY`)
3. artifact files under `.cache/perf-hxrt/results`

Primary files:

- `current.json` (full current run)
- `comparison.json` (warning + hard-fail gate decisions)
- `raw_metrics.tsv` (flat metrics table)
- `summary.md` (human-readable report, including metal target tracking status for `hot_loop_inproc`)
- `failures.txt` (hard-fail gate violations, if any)

## Updating the baseline safely

1. Run `npm run test:perf:hxrt:update-baseline`.
2. Run `npm run test:perf:hxrt` once to confirm compare mode is stable.
3. Commit `scripts/ci/perf/hxrt-baseline.json` with an explanation in the commit message.

Only update the baseline when you intentionally change runtime/perf expectations, not to hide regressions.
