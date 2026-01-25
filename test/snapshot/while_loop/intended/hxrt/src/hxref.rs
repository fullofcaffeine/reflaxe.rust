use std::cell::RefCell;
use std::rc::Rc;

/// `hxrt::hxref`
///
/// Tiny helpers for the Rust representation of Haxe "object references".
///
/// Why
/// - reflaxe.rust represents Haxe class instances as `Rc<RefCell<T>>` (type-aliased as `HxRef<T>` in
///   generated crates).
/// - Some stdlib containers (e.g. `haxe.ds.ObjectMap`) need a stable, identity-based key derived from
///   the underlying reference.
///
/// What
/// - `HxRefLike`: a trait implemented for `Rc<RefCell<T>>` that can produce a stable pointer identity.
/// - `ptr_id`: a small helper returning a hex string id for any `HxRefLike`.
///
/// How
/// - `ptr_usize()` uses `Rc::as_ptr` to obtain a stable address for the allocation backing the `Rc`.
/// - `ptr_id()` formats it as a hex string (no `0x` prefix) for convenient use as a map key.
pub trait HxRefLike {
    fn ptr_usize(&self) -> usize;
}

impl<T> HxRefLike for Rc<RefCell<T>> {
    fn ptr_usize(&self) -> usize {
        Rc::as_ptr(self) as usize
    }
}

pub fn ptr_id<K: HxRefLike>(key: &K) -> String {
    format!("{:x}", key.ptr_usize())
}

