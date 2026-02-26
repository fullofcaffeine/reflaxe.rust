# Spike: `hxrt::cell` single-thread fast mode

## Goal

Evaluate whether `hxrt::cell` should support an optional single-thread storage mode (for builds without `sys.thread.*`) to reduce lock overhead.

## Current state

- `runtime/hxrt/src/cell.rs` uses:
  - `HxRc<T> = Arc<T>`
  - `HxCell<T>` backed by `parking_lot::RwLock<T>`
  - `HxRef<T> = Option<Arc<HxCell<T>>>`
- This representation is intentionally thread-safe by default so generated code can cross OS thread boundaries when needed.

## Prototype method

Microbench-only spike (not integrated into `hxrt`) comparing three primitives under a read+write hot loop:

- `Arc<RwLock<i64>>` (current model)
- `Rc<RefCell<i64>>` (candidate single-thread model)
- `Rc<Cell<i64>>` (best-case single-thread scalar cell)

Workload:

- 25,000,000 iterations
- each iteration performs one read and one write
- `std::hint::black_box` used to avoid optimizer elimination

## Findings

Two release runs from the same local machine/session:

1. Run A
   - `RwLock`: `276.312 ms`
   - `RefCell`: `70.691 ms`
   - `Cell`: `71.060 ms`
   - `RefCell vs RwLock`: `0.256x` (about `3.9x` faster)
2. Run B
   - `RwLock`: `256.772 ms`
   - `RefCell`: `70.232 ms`
   - `Cell`: `70.578 ms`
   - `RefCell vs RwLock`: `0.274x` (about `3.6x` faster)

Interpretation:

- For pure single-thread borrow traffic, lock-free single-thread cells have meaningful upside.
- `RefCell` and `Cell` were effectively similar in this mixed read/write scalar scenario.

## Integration risks

1. Global type identity drift:
   - Switching `HxRc` between `Arc` and `Rc` changes trait bounds (`Send`/`Sync`) and can affect generated trait-object boundaries.
2. Feature-coupling complexity:
   - `thread` feature gating in `runtime/hxrt/Cargo.toml` is currently additive, but `cell.rs` is foundational and used across most modules.
3. Semantic split cost:
   - A dual storage backend increases test matrix and raises risk of profile/feature-specific regressions.
4. Crate interface stability:
   - Generated code assumes one canonical `HxRef` model; polymorphic backend switching would need stronger compile-time guardrails.

## Recommendation

`NO-GO` for immediate rollout in mainline runtime behavior.

Reason:

- Measured upside is real, but integration risk is high relative to current compiler/runtime maturity.
- This should follow a broader runtime decomposition step (where cell backend selection can be cleanly feature-gated and tested in isolation).

## If resumed later

1. Introduce an explicit runtime feature (example: `cell_single_thread`) with hard incompatibility against `thread`.
2. Keep API shape (`HxRef`, `borrow`, `borrow_mut`) stable across both implementations.
3. Add dedicated runtime tests in both modes (null dereference behavior, borrow panic behavior, alias semantics).
4. Add perf case(s) to `scripts/ci/perf-hxrt-overhead.sh` so gains are tracked as artifacts, not anecdotal.
