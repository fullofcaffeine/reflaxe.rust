//! Minimal async bridge used by the Haxe -> Rust async preview.
//!
//! Design:
//! - Keep runtime ownership explicit with a single concrete future type alias.
//! - Keep sync/async boundary explicit via `block_on`.

use std::future::Future;
use std::pin::Pin;
use std::time::Duration;

pub type HxFuture<T> = Pin<Box<dyn Future<Output = T> + Send + 'static>>;

#[inline]
pub fn ready<T>(value: T) -> HxFuture<T>
where
    T: Send + 'static,
{
    Box::pin(async move { value })
}

#[inline]
pub fn block_on<T>(future: HxFuture<T>) -> T {
    pollster::block_on(future)
}

#[inline]
pub fn sleep(duration: Duration) -> HxFuture<()> {
    Box::pin(async move {
        futures_timer::Delay::new(duration).await;
    })
}

#[inline]
pub fn sleep_ms(ms: i32) -> HxFuture<()> {
    let clamped = if ms < 0 { 0 } else { ms as u64 };
    sleep(Duration::from_millis(clamped))
}
