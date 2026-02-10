use parking_lot::{RwLock, RwLockReadGuard, RwLockWriteGuard};
use std::sync::{Arc, Weak};

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
pub struct HxCell<T> {
    self_weak: Option<Weak<HxCell<T>>>,
    lock: RwLock<T>,
}

impl<T> HxCell<T> {
    #[inline]
    pub fn new(value: T) -> Self {
        Self {
            self_weak: None,
            lock: RwLock::new(value),
        }
    }

    /// Return a `HxRef<T>` pointing at the `HxCell<T>` allocation that owns `self`.
    ///
    /// This is only available for cells that live inside a `HxRef<T>` (i.e. allocated via
    /// `HxRef::new`). For standalone cells (static vars, locals), this throws "Null Access".
    ///
    /// Why
    /// - Haxe allows passing `this` as a value (`foo(this)`), returning it, storing it, etc.
    /// - Generated instance methods receive `&HxRefCell<T>` (`&HxCell<T>`), which is not itself an
    ///   owning reference.
    ///
    /// How
    /// - `HxRef::new` allocates `Arc<HxCell<T>>` via `Arc::new_cyclic`, storing a `Weak` pointer to
    ///   itself into `self_weak`.
    /// - `self_ref()` upgrades that `Weak` back into an `Arc` and wraps it as `HxRef<T>`.
    #[inline]
    pub fn self_ref(&self) -> HxRef<T> {
        match &self.self_weak {
            Some(w) => match w.upgrade() {
                Some(rc) => HxRef(Some(rc)),
                None => crate::exception::throw(crate::dynamic::from(String::from("Null Access"))),
            },
            None => crate::exception::throw(crate::dynamic::from(String::from("Null Access"))),
        }
    }

    #[inline]
    pub fn borrow(&self) -> RwLockReadGuard<'_, T> {
        self.lock.read()
    }

    #[inline]
    pub fn borrow_mut(&self) -> RwLockWriteGuard<'_, T> {
        self.lock.write()
    }
}

/// Nullable reference to an interior-mutable Haxe value.
///
/// Why
/// - In Haxe, all class instances can be `null` by default.
/// - Rust references and `Arc<T>` are non-nullable, so we need an explicit null representation.
/// - We also want a consistent `borrow()` / `borrow_mut()` API for generated code.
///
/// What
/// - Wraps `Option<Arc<HxCell<T>>>`.
/// - `Default` is `null`, so uninitialized fields/locals behave like Haxe.
///
/// How
/// - `borrow()` / `borrow_mut()` throw a catchable Haxe exception on null dereference
///   (implemented via `hxrt::exception::throw`, not a Rust `unwrap()` panic).
#[derive(Debug)]
pub struct HxRef<T>(Option<HxRc<HxCell<T>>>);

impl<T> Clone for HxRef<T> {
    #[inline]
    fn clone(&self) -> Self {
        Self(self.0.clone())
    }
}

impl<T> Default for HxRef<T> {
    #[inline]
    fn default() -> Self {
        Self::null()
    }
}

impl<T> HxRef<T> {
    #[inline]
    pub fn new(value: T) -> Self {
        // Store a self-`Weak` inside `HxCell` so instance methods can recover a `HxRef<T>` for `this`.
        Self(Some(HxRc::new_cyclic(|weak| HxCell {
            self_weak: Some(weak.clone()),
            lock: RwLock::new(value),
        })))
    }

    #[inline]
    pub fn null() -> Self {
        Self(None)
    }

    #[inline]
    pub fn is_null(&self) -> bool {
        self.0.is_none()
    }

    #[inline]
    pub fn is_some(&self) -> bool {
        self.0.is_some()
    }

    #[inline]
    pub fn ptr_eq(&self, other: &Self) -> bool {
        match (&self.0, &other.0) {
            (None, None) => true,
            (Some(a), Some(b)) => HxRc::ptr_eq(a, b),
            _ => false,
        }
    }

    #[inline]
    fn unwrap_cell(&self) -> &HxCell<T> {
        match &self.0 {
            Some(rc) => rc.as_ref(),
            None => crate::exception::throw(crate::dynamic::from(String::from("Null Access"))),
        }
    }

    #[inline]
    pub fn borrow(&self) -> RwLockReadGuard<'_, T> {
        self.unwrap_cell().borrow()
    }

    #[inline]
    pub fn borrow_mut(&self) -> RwLockWriteGuard<'_, T> {
        self.unwrap_cell().borrow_mut()
    }
}

impl<T> std::ops::Deref for HxRef<T> {
    type Target = HxCell<T>;

    #[inline]
    fn deref(&self) -> &Self::Target {
        self.unwrap_cell()
    }
}

impl<T> From<HxRc<HxCell<T>>> for HxRef<T> {
    #[inline]
    fn from(value: HxRc<HxCell<T>>) -> Self {
        Self(Some(value))
    }
}

impl<T> HxRef<T> {
    #[inline]
    pub fn as_arc_opt(&self) -> Option<&HxRc<HxCell<T>>> {
        self.0.as_ref()
    }
}

/// Nullable shared reference for unsized values (trait objects, closures, etc.).
///
/// This is used for values that cannot live inside `HxCell<T>` (because `T` is `?Sized`),
/// such as `dyn Trait` objects.
#[derive(Debug)]
pub struct HxDynRef<T: ?Sized>(Option<HxRc<T>>);

impl<T: ?Sized> Clone for HxDynRef<T> {
    #[inline]
    fn clone(&self) -> Self {
        Self(self.0.clone())
    }
}

impl<T: ?Sized> Default for HxDynRef<T> {
    #[inline]
    fn default() -> Self {
        Self::null()
    }
}

impl<T: ?Sized> HxDynRef<T> {
    #[inline]
    pub fn new(value: HxRc<T>) -> Self {
        Self(Some(value))
    }

    #[inline]
    pub fn null() -> Self {
        Self(None)
    }

    #[inline]
    pub fn is_null(&self) -> bool {
        self.0.is_none()
    }

    #[inline]
    pub fn is_some(&self) -> bool {
        self.0.is_some()
    }

    #[inline]
    pub fn ptr_eq(&self, other: &Self) -> bool {
        match (&self.0, &other.0) {
            (None, None) => true,
            (Some(a), Some(b)) => HxRc::ptr_eq(a, b),
            _ => false,
        }
    }

    #[inline]
    fn unwrap_arc(&self) -> &HxRc<T> {
        match &self.0 {
            Some(rc) => rc,
            None => crate::exception::throw(crate::dynamic::from(String::from("Null Access"))),
        }
    }
}

impl<T: ?Sized> std::ops::Deref for HxDynRef<T> {
    type Target = T;

    #[inline]
    fn deref(&self) -> &Self::Target {
        self.unwrap_arc().as_ref()
    }
}

impl<T: ?Sized> From<HxRc<T>> for HxDynRef<T> {
    #[inline]
    fn from(value: HxRc<T>) -> Self {
        Self(Some(value))
    }
}

impl<T: ?Sized> HxDynRef<T> {
    #[inline]
    pub fn as_arc_opt(&self) -> Option<&HxRc<T>> {
        self.0.as_ref()
    }
}
