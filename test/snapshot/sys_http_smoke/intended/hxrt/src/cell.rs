use parking_lot::{RwLock, RwLockReadGuard, RwLockWriteGuard};
use std::sync::Arc;

/// Thread-safe shared reference type used across generated crates and the hxrt runtime.
///
/// Why
/// - `reflaxe.rust` needs to support `sys.thread.*`, which implies running Haxe code on OS threads.
/// - The original `Rc<RefCell<T>>` representation cannot cross threads (`!Send/!Sync`).
///
/// What
/// - `HxRc<T>`: shared ownership (currently `Arc<T>`).
/// - `HxCell<T>`: interior-mutability cell with `borrow()` / `borrow_mut()` API compatible with
///   generated code (implemented with a `RwLock`).
/// - `HxRef<T>`: the canonical "Haxe object reference" (`HxRc<HxCell<T>>`).
///
/// How
/// - `borrow()` yields a read guard, `borrow_mut()` yields a write guard.
/// - Using a `RwLock` keeps repeated reads cheap-ish and avoids accidental self-deadlocks that would
///   be easy to introduce with a plain mutex in generated expressions.
pub type HxRc<T> = Arc<T>;

#[derive(Debug, Default)]
pub struct HxCell<T>(RwLock<T>);

impl<T> HxCell<T> {
    #[inline]
    pub fn new(value: T) -> Self {
        Self(RwLock::new(value))
    }

    #[inline]
    pub fn borrow(&self) -> RwLockReadGuard<'_, T> {
        self.0.read()
    }

    #[inline]
    pub fn borrow_mut(&self) -> RwLockWriteGuard<'_, T> {
        self.0.write()
    }
}

pub type HxRef<T> = HxRc<HxCell<T>>;
