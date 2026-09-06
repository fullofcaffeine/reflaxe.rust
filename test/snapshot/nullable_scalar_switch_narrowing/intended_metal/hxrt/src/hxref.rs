use std::sync::Arc;

use crate::cell::{HxDynRef, HxRef};

/// `hxrt::hxref`
///
/// Tiny helpers for the Rust representation of Haxe "object references".
///
/// Why
/// - reflaxe.rust represents Haxe class instances as `HxRef<T>` (currently `Arc<...>`), so values can
///   safely cross OS-thread boundaries when `sys.thread.*` is used.
/// - Some stdlib containers (e.g. `haxe.ds.ObjectMap`) need a stable, identity-based key derived from
///   the underlying reference.
///
/// What
/// - `HxRefLike`: a trait implemented for `Arc<T>` that can produce a stable pointer identity.
/// - `ptr_id`: a small helper returning a hex string id for any `HxRefLike`.
///
/// How
/// - `ptr_usize()` uses `Arc::as_ptr` to obtain a stable address for the allocation backing the `Arc`.
/// - `ptr_id()` formats it as a hex string (no `0x` prefix) for convenient use as a map key.
pub trait HxRefLike {
    fn ptr_usize(&self) -> usize;
}

impl<T: ?Sized> HxRefLike for Arc<T> {
    fn ptr_usize(&self) -> usize {
        Arc::as_ptr(self) as *const () as usize
    }
}

impl<T> HxRefLike for HxRef<T> {
    fn ptr_usize(&self) -> usize {
        match self.as_arc_opt() {
            Some(rc) => Arc::as_ptr(rc) as *const () as usize,
            None => 0,
        }
    }
}

impl<T: ?Sized> HxRefLike for HxDynRef<T> {
    fn ptr_usize(&self) -> usize {
        match self.as_arc_opt() {
            Some(rc) => Arc::as_ptr(rc) as *const () as usize,
            None => 0,
        }
    }
}

#[inline]
pub fn ptr_eq<A: HxRefLike, B: HxRefLike>(a: &A, b: &B) -> bool {
    a.ptr_usize() == b.ptr_usize()
}

pub fn ptr_id<K: HxRefLike>(key: &K) -> String {
    format!("{:x}", key.ptr_usize())
}
