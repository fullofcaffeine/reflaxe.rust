use crate::dynamic::Dynamic;
use std::cell::{Cell, RefCell};
use std::sync::OnceLock;

thread_local! {
    static NEXT_ID: Cell<u64> = const { Cell::new(1) };
    static ACTIVE_ID: Cell<u64> = const { Cell::new(0) };
    static PAYLOAD: RefCell<Option<Dynamic>> = const { RefCell::new(None) };
    static SUPPRESS_PANIC_OUTPUT: Cell<bool> = const { Cell::new(false) };
}

static HOOK_INSTALLED: OnceLock<()> = OnceLock::new();

fn ensure_panic_hook_installed() {
    HOOK_INSTALLED.get_or_init(|| {
        let prev = std::panic::take_hook();
        std::panic::set_hook(Box::new(move |info| {
            // A caught Haxe throw is implemented via `panic_any(id)`. When we catch it via
            // `catch_unwind`, we suppress the default panic hook output to avoid noisy stderr
            // (caught exceptions should be silent, like other Haxe targets).
            let suppress = SUPPRESS_PANIC_OUTPUT.with(|s| s.get());
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
    SUPPRESS_PANIC_OUTPUT.with(|s| s.set(true));

    struct SuppressGuard;
    impl Drop for SuppressGuard {
        fn drop(&mut self) {
            SUPPRESS_PANIC_OUTPUT.with(|s| s.set(false));
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
