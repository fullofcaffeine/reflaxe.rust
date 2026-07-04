//! Async bridge used by Rust-first async surfaces (`std/rust/async/*`).
//!
//! Why
//! - Keep async ownership explicit with one concrete future type.
//! - Keep sync/async boundaries explicit (`block_on`) instead of implicit runtime magic.
//! - Provide a small runtime adapter seam so projects can stay on the default lightweight
//!   path (`pollster` + `futures-timer`) or opt into a tokio-backed adapter when needed.
//!
//! What
//! - `HxFuture<T>`: boxed + pinned future shape used by generated code.
//! - `ready`, `block_on`, `sleep`, `sleep_ms`: baseline async helpers.
//! - `spawn`: async task helper that runs a future on separate execution.
//! - `select_first`: race two futures and return whichever value resolves first.
//! - `timeout`, `timeout_ms`: race a future against a timer and return `Option<T>`.
//! - `enable_tokio_runtime` / `disable_tokio_runtime` / `is_tokio_runtime_enabled`:
//!   adapter toggles (feature-gated by `async_tokio`).

use futures::future::{select, Either};
use std::future::Future;
use std::pin::Pin;
use std::time::Duration;

#[cfg(feature = "thread")]
use crate::cell::{HxDynRef, HxRc, HxRef};
#[cfg(feature = "thread")]
use crate::concurrent::TaskHandle;

#[cfg(feature = "async_tokio")]
use std::sync::atomic::{AtomicBool, Ordering};

pub type HxFuture<T> = Pin<Box<dyn Future<Output = T> + Send + 'static>>;

#[cfg(feature = "async_tokio")]
static TOKIO_RUNTIME_ENABLED: AtomicBool = AtomicBool::new(false);

#[inline]
pub fn ready<T>(value: T) -> HxFuture<T>
where
    T: Send + 'static,
{
    Box::pin(async move { value })
}

#[cfg(feature = "async_tokio")]
#[inline]
fn use_tokio_runtime() -> bool {
    TOKIO_RUNTIME_ENABLED.load(Ordering::Relaxed)
}

#[cfg(not(feature = "async_tokio"))]
#[inline]
fn use_tokio_runtime() -> bool {
    false
}

#[cfg(feature = "async_tokio")]
fn tokio_block_on<T>(future: HxFuture<T>) -> T {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_time()
        .build()
        .unwrap_or_else(|err| panic!("failed to create tokio runtime: {err}"));
    runtime.block_on(future)
}

/// Enable tokio runtime adapter for subsequent async helper calls.
#[cfg(feature = "async_tokio")]
pub fn enable_tokio_runtime() {
    TOKIO_RUNTIME_ENABLED.store(true, Ordering::Relaxed);
}

/// Disable tokio runtime adapter and return to default async helpers.
pub fn disable_tokio_runtime() {
    #[cfg(feature = "async_tokio")]
    {
        TOKIO_RUNTIME_ENABLED.store(false, Ordering::Relaxed);
    }
}

/// Returns whether the tokio adapter is currently enabled.
pub fn is_tokio_runtime_enabled() -> bool {
    use_tokio_runtime()
}

#[inline]
pub fn block_on<T>(future: HxFuture<T>) -> T {
    #[cfg(feature = "async_tokio")]
    if use_tokio_runtime() {
        return tokio_block_on(future);
    }

    pollster::block_on(future)
}

#[inline]
pub fn sleep(duration: Duration) -> HxFuture<()> {
    #[cfg(feature = "async_tokio")]
    if use_tokio_runtime() {
        return Box::pin(async move {
            tokio::time::sleep(duration).await;
        });
    }

    Box::pin(async move {
        futures_timer::Delay::new(duration).await;
    })
}

#[inline]
pub fn sleep_ms(ms: i32) -> HxFuture<()> {
    let clamped = if ms < 0 { 0 } else { ms as u64 };
    sleep(Duration::from_millis(clamped))
}

/// Spawn an async job into a thread-backed task handle.
#[cfg(feature = "thread")]
pub fn task_spawn<T>(job: HxDynRef<dyn Fn() -> HxFuture<T> + Send + Sync>) -> HxRef<TaskHandle<T>>
where
    T: Send + 'static,
{
    let job: HxRc<dyn Fn() -> HxFuture<T> + Send + Sync> = match job.as_arc_opt() {
        Some(rc) => rc.clone(),
        None => panic!("Null Access"),
    };

    let blocking_job: HxRc<dyn Fn() -> T + Send + Sync> = HxRc::new(move || block_on(job()));
    crate::concurrent::task_spawn(HxDynRef::new(blocking_job))
}

/// Join a task spawned through `task_spawn`.
#[cfg(feature = "thread")]
pub fn task_join<T>(task: &HxRef<TaskHandle<T>>) -> T {
    crate::concurrent::task_join(task)
}

/// Spawn a future and return a future that resolves with the spawned output.
pub fn spawn<T>(future: HxFuture<T>) -> HxFuture<T>
where
    T: Send + 'static,
{
    #[cfg(feature = "async_tokio")]
    if use_tokio_runtime() {
        return Box::pin(async move {
            tokio::spawn(future)
                .await
                .unwrap_or_else(|err| panic!("tokio async task panicked: {err}"))
        });
    }

    Box::pin(async move {
        let (sender, receiver) = std::sync::mpsc::sync_channel::<T>(1);
        std::thread::spawn(move || {
            let out = block_on(future);
            let _ = sender.send(out);
        });

        loop {
            match receiver.try_recv() {
                Ok(value) => return value,
                Err(std::sync::mpsc::TryRecvError::Empty) => {
                    sleep_ms(1).await;
                }
                Err(std::sync::mpsc::TryRecvError::Disconnected) => {
                    panic!("async task disconnected before producing a value");
                }
            }
        }
    })
}

/// Race two futures of the same output type and return the first completed value.
pub fn select_first<T>(left: HxFuture<T>, right: HxFuture<T>) -> HxFuture<T>
where
    T: Send + 'static,
{
    #[cfg(feature = "async_tokio")]
    if use_tokio_runtime() {
        return Box::pin(async move {
            tokio::select! {
                value = left => value,
                value = right => value,
            }
        });
    }

    Box::pin(async move {
        match select(left, right).await {
            Either::Left((value, _pending_right)) => value,
            Either::Right((value, _pending_left)) => value,
        }
    })
}

/// Race a future against `duration` and return `Some(value)` on success, `None` on timeout.
pub fn timeout<T>(future: HxFuture<T>, duration: Duration) -> HxFuture<Option<T>>
where
    T: Send + 'static,
{
    #[cfg(feature = "async_tokio")]
    if use_tokio_runtime() {
        return Box::pin(async move {
            match tokio::time::timeout(duration, future).await {
                Ok(value) => Some(value),
                Err(_) => None,
            }
        });
    }

    Box::pin(async move {
        match select(future, sleep(duration)).await {
            Either::Left((value, _pending_sleep)) => Some(value),
            Either::Right((_timeout_elapsed, _pending_future)) => None,
        }
    })
}

/// Millisecond helper for `timeout(...)`.
pub fn timeout_ms<T>(future: HxFuture<T>, ms: i32) -> HxFuture<Option<T>>
where
    T: Send + 'static,
{
    let clamped = if ms < 0 { 0 } else { ms as u64 };
    timeout(future, Duration::from_millis(clamped))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[cfg(feature = "async_tokio")]
    use std::sync::Mutex;

    #[cfg(feature = "async_tokio")]
    static TOKIO_ADAPTER_TEST_LOCK: Mutex<()> = Mutex::new(());

    #[test]
    fn ready_block_on_roundtrip() {
        assert_eq!(block_on(ready(42)), 42);
    }

    #[cfg(feature = "thread")]
    #[test]
    fn task_spawn_join_roundtrip() {
        let task_job: HxRc<dyn Fn() -> HxFuture<i32> + Send + Sync> = HxRc::new(|| ready(33));
        let task = task_spawn(HxDynRef::new(task_job));
        assert_eq!(task_join(&task), 33);
    }

    #[test]
    fn spawn_roundtrip() {
        #[cfg(feature = "async_tokio")]
        let _lock = TOKIO_ADAPTER_TEST_LOCK.lock().unwrap();
        #[cfg(feature = "async_tokio")]
        disable_tokio_runtime();

        let future = Box::pin(async move {
            sleep_ms(5).await;
            7
        });
        assert_eq!(block_on(spawn(future)), 7);
        #[cfg(feature = "async_tokio")]
        disable_tokio_runtime();
    }

    #[test]
    fn timeout_ms_returns_none() {
        #[cfg(feature = "async_tokio")]
        let _lock = TOKIO_ADAPTER_TEST_LOCK.lock().unwrap();
        #[cfg(feature = "async_tokio")]
        disable_tokio_runtime();

        let slow = Box::pin(async move {
            sleep_ms(25).await;
            99
        });
        assert_eq!(block_on(timeout_ms(slow, 1)), None);
        #[cfg(feature = "async_tokio")]
        disable_tokio_runtime();
    }

    #[test]
    fn timeout_ms_returns_some() {
        #[cfg(feature = "async_tokio")]
        let _lock = TOKIO_ADAPTER_TEST_LOCK.lock().unwrap();
        #[cfg(feature = "async_tokio")]
        disable_tokio_runtime();

        let fast = Box::pin(async move {
            sleep_ms(1).await;
            11
        });
        assert_eq!(block_on(timeout_ms(fast, 50)), Some(11));
        #[cfg(feature = "async_tokio")]
        disable_tokio_runtime();
    }

    #[test]
    fn select_first_returns_first_value() {
        #[cfg(feature = "async_tokio")]
        let _lock = TOKIO_ADAPTER_TEST_LOCK.lock().unwrap();
        #[cfg(feature = "async_tokio")]
        disable_tokio_runtime();

        let fast = Box::pin(async move {
            sleep_ms(1).await;
            21
        });
        let slow = Box::pin(async move {
            sleep_ms(20).await;
            99
        });
        assert_eq!(block_on(select_first(fast, slow)), 21);
        #[cfg(feature = "async_tokio")]
        disable_tokio_runtime();
    }

    #[cfg(feature = "async_tokio")]
    #[test]
    fn tokio_runtime_adapter_roundtrip() {
        let _lock = TOKIO_ADAPTER_TEST_LOCK.lock().unwrap();
        disable_tokio_runtime();
        assert!(!is_tokio_runtime_enabled());

        enable_tokio_runtime();
        assert!(is_tokio_runtime_enabled());

        let value = block_on(Box::pin(async move {
            sleep_ms(1).await;
            5
        }));
        assert_eq!(value, 5);

        disable_tokio_runtime();
        assert!(!is_tokio_runtime_enabled());
    }

    #[cfg(feature = "async_tokio")]
    #[test]
    fn select_first_works_with_tokio_adapter() {
        let _lock = TOKIO_ADAPTER_TEST_LOCK.lock().unwrap();
        enable_tokio_runtime();

        let fast = Box::pin(async move {
            sleep_ms(1).await;
            8
        });
        let slow = Box::pin(async move {
            sleep_ms(20).await;
            9
        });

        assert_eq!(block_on(select_first(fast, slow)), 8);

        disable_tokio_runtime();
    }
}
