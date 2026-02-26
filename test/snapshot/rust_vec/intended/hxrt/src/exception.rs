use crate::dynamic::Dynamic;
use std::cell::{Cell, RefCell};
use std::sync::OnceLock;

thread_local! {
    static NEXT_ID: Cell<u64> = const { Cell::new(1) };
    static ACTIVE_ID: Cell<u64> = const { Cell::new(0) };
    static PAYLOAD: RefCell<Option<Dynamic>> = const { RefCell::new(None) };
    // Nested `catch_unwind` calls are common (for example stdlib I/O helpers wrapped by
    // higher-level try/catch blocks). Use a depth counter so inner frames don't disable
    // suppression while an outer frame is still active.
    static SUPPRESS_PANIC_OUTPUT_DEPTH: Cell<u32> = const { Cell::new(0) };
}

static HOOK_INSTALLED: OnceLock<()> = OnceLock::new();

fn ensure_panic_hook_installed() {
    HOOK_INSTALLED.get_or_init(|| {
        let prev = std::panic::take_hook();
        std::panic::set_hook(Box::new(move |info| {
            // A caught Haxe throw is implemented via `panic_any(id)`. When we catch it via
            // `catch_unwind`, we suppress the default panic hook output to avoid noisy stderr
            // (caught exceptions should be silent, like other Haxe targets).
            let suppress = SUPPRESS_PANIC_OUTPUT_DEPTH.with(|s| s.get() > 0);
            if suppress {
                if let Some(id) = info.payload().downcast_ref::<u64>() {
                    let active = ACTIVE_ID.with(|c| c.get());
                    if *id == active && active != 0 {
                        return;
                    }
                }
            }

            prev(info);
        }));
    });
}

/// Throw a value using a panic-id + thread-local payload mechanism.
///
/// WHY
/// - Rust panic payloads must be `Send`, but Haxe thrown values are not necessarily `Send`.
/// - We keep the payload in thread-local storage and panic with a small `u64` id instead.
pub fn throw(value: Dynamic) -> ! {
    let id = NEXT_ID.with(|c| {
        let id = c.get();
        c.set(id.wrapping_add(1));
        id
    });

    ACTIVE_ID.with(|c| c.set(id));
    PAYLOAD.with(|p| *p.borrow_mut() = Some(value));

    std::panic::panic_any(id);
}

/// Catch Haxe throws across unwind boundaries.
///
/// Returns:
/// - `Ok(r)` when `f()` completes normally
/// - `Err(dynamic)` when a value was thrown via `hxrt::exception::throw`
///
/// Re-panics for non-Haxe panics (or missing payloads).
pub fn catch_unwind<F, R>(f: F) -> Result<R, Dynamic>
where
    F: FnOnce() -> R,
{
    ensure_panic_hook_installed();
    SUPPRESS_PANIC_OUTPUT_DEPTH.with(|s| s.set(s.get().saturating_add(1)));

    struct SuppressGuard;
    impl Drop for SuppressGuard {
        fn drop(&mut self) {
            SUPPRESS_PANIC_OUTPUT_DEPTH.with(|s| {
                let current = s.get();
                if current > 0 {
                    s.set(current - 1);
                }
            });
        }
    }
    let _guard = SuppressGuard;

    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(f)) {
        Ok(v) => Ok(v),
        Err(panic_payload) => {
            if let Some(id) = panic_payload.downcast_ref::<u64>() {
                let active = ACTIVE_ID.with(|c| c.get());
                if *id == active {
                    let found = PAYLOAD.with(|p| p.borrow_mut().take());
                    ACTIVE_ID.with(|c| c.set(0));
                    if let Some(v) = found {
                        return Err(v);
                    }
                }

                // Unknown/missing id: not ours (or already consumed). Re-raise the original panic.
                std::panic::resume_unwind(panic_payload);
            } else {
                std::panic::resume_unwind(panic_payload);
            }
        }
    }
}

/// Re-throw a previously caught payload.
///
/// Useful when a `try/catch` does not match the caught value's type; we rethrow so
/// outer catch blocks can handle it.
pub fn rethrow(value: Dynamic) -> ! {
    throw(value)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dynamic_i32(value: i32) -> Dynamic {
        Dynamic::from(value)
    }

    #[test]
    fn nested_catch_unwind_keeps_suppression_depth_until_outer_returns() {
        SUPPRESS_PANIC_OUTPUT_DEPTH.with(|d| d.set(0));

        let outer = catch_unwind(|| {
            let inner = catch_unwind(|| {
                throw(dynamic_i32(7));
            });

            assert!(inner.is_err());
            SUPPRESS_PANIC_OUTPUT_DEPTH.with(|d| {
                // While still inside the outer catch, nested depth must remain active.
                assert!(d.get() >= 1);
            });
            11
        });

        assert_eq!(outer.unwrap(), 11);
        SUPPRESS_PANIC_OUTPUT_DEPTH.with(|d| assert_eq!(d.get(), 0));
    }

    #[test]
    fn rethrow_from_inner_catch_reaches_outer_catch() {
        let outer = catch_unwind(|| {
            let inner = catch_unwind(|| {
                throw(dynamic_i32(42));
            });

            match inner {
                Ok(_) => 0,
                Err(ex) => rethrow(ex),
            }
        });

        let err = outer.expect_err("outer catch should receive rethrow");
        let got = err.downcast_ref::<i32>().copied();
        assert_eq!(got, Some(42));
    }
}
