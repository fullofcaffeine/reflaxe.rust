use crate::anon::Anon;
use crate::cell::HxRef;
use std::any::Any;
use std::fmt;
use std::iter::Peekable;

/// Builds the Haxe anonymous `{ key, value }` record yielded by key-value iterators.
///
/// Why
/// - Haxe key-value iterator items are ordinary anonymous objects, not nominal value tuples.
/// - They must preserve shared mutation, aliasing, and reference equality after crossing native
///   map helper boundaries.
///
/// What
/// - Returns the same `HxRef<Anon>` representation used by compiler-lowered record literals.
///
/// How
/// - Stores the two typed values through the existing anonymous-object boundary and introduces no
///   second iterator-specific object model.
pub fn key_value<K, V>(key: K, value: V) -> HxRef<Anon>
where
    K: Any + Clone + Send + Sync + 'static,
    V: Any + Clone + Send + Sync + 'static,
{
    let mut record = Anon::new();
    record.set("key", key);
    record.set("value", value);
    HxRef::new(record)
}

/// `hxrt::iter::Iter<T>`
///
/// A small "Haxe-style iterator" adapter.
///
/// Why
/// - Haxe's `Iterator<T>` is defined by the presence of `hasNext()` / `next()`.
/// - The Rust backend often produces Rust-native iterators, but some stdlib helpers
///   (and some user code) still call the manual iterator protocol.
///
/// What
/// - Owns either the existing fast vector iterator or a pair of lazy protocol callbacks.
/// - Exposes `has_next()` / `next()` as `&self` methods using shared interior mutability.
///
/// How
/// - `from_vec` retains the unboxed `Vec<T>::IntoIter` fast path used by ordinary generated code.
/// - `from_callbacks` is reserved for compiler-generated bridges from nominal Haxe iterator objects
///   whose values cannot be materialized eagerly without changing runtime semantics.
/// - Clones share one `IterState<T>`, preserving Haxe cursor aliasing in both representations.
#[derive(Debug)]
pub struct Iter<T> {
    iter: HxRef<IterState<T>>,
}

enum IterState<T> {
    Values(Peekable<std::vec::IntoIter<T>>),
    Callbacks {
        has_next: Box<dyn Fn() -> bool + Send + Sync>,
        next: Box<dyn Fn() -> T + Send + Sync>,
    },
}

impl<T> fmt::Debug for IterState<T>
where
    T: fmt::Debug,
{
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Values(values) => formatter.debug_tuple("Values").field(values).finish(),
            Self::Callbacks { .. } => formatter.write_str("Callbacks(..)"),
        }
    }
}

impl<T> Clone for Iter<T> {
    fn clone(&self) -> Self {
        Self {
            iter: self.iter.clone(),
        }
    }
}

pub struct IntoIter<T> {
    inner: Iter<T>,
}

impl<T> Iterator for IntoIter<T> {
    type Item = T;

    fn next(&mut self) -> Option<Self::Item> {
        if self.inner.has_next() {
            Some(self.inner.next())
        } else {
            None
        }
    }
}

impl<T> IntoIterator for Iter<T> {
    type Item = T;
    type IntoIter = IntoIter<T>;

    fn into_iter(self) -> Self::IntoIter {
        IntoIter { inner: self }
    }
}

impl<T> IntoIterator for &Iter<T> {
    type Item = T;
    type IntoIter = IntoIter<T>;

    fn into_iter(self) -> Self::IntoIter {
        IntoIter {
            inner: self.clone(),
        }
    }
}

impl<T> Iter<T> {
    pub fn from_vec(vec: Vec<T>) -> Self {
        Self {
            iter: HxRef::new(IterState::Values(vec.into_iter().peekable())),
        }
    }

    /// Builds a shared Haxe iterator from lazy protocol operations.
    ///
    /// Why
    /// - A nominal Haxe iterator may read mutable source state when `next()` executes.
    /// - Converting that object to a vector at a structural `Iterator<T>` boundary would freeze the
    ///   values too early and violate source semantics.
    ///
    /// What
    /// - Stores the compiler-generated `hasNext` and `next` adapters behind one shared cursor value.
    ///
    /// How
    /// - Each callback captures the same generated iterator object through cloned `HxRef` handles.
    /// - Only this explicitly lazy path boxes callbacks; `from_vec` remains an unboxed iterator.
    pub fn from_callbacks<H, N>(has_next: H, next: N) -> Self
    where
        H: Fn() -> bool + Send + Sync + 'static,
        N: Fn() -> T + Send + Sync + 'static,
    {
        Self {
            iter: HxRef::new(IterState::Callbacks {
                has_next: Box::new(has_next),
                next: Box::new(next),
            }),
        }
    }

    pub fn has_next(&self) -> bool {
        let mut iter = self.iter.borrow_mut();
        match &mut *iter {
            IterState::Values(values) => values.peek().is_some(),
            IterState::Callbacks { has_next, .. } => has_next(),
        }
    }

    #[allow(non_snake_case)]
    pub fn hasNext(&self) -> bool {
        self.has_next()
    }

    pub fn next(&self) -> T {
        let mut iter = self.iter.borrow_mut();
        match &mut *iter {
            IterState::Values(values) => values
                .next()
                .expect("hxrt::iter::Iter.next() called when exhausted"),
            IterState::Callbacks { next, .. } => next(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{key_value, Iter};
    use crate::cell::HxRef;

    #[test]
    fn callback_iter_reads_lazily_and_shares_cursor() {
        let state = HxRef::new(vec![7_i32]);
        let has_state = state.clone();
        let next_state = state.clone();
        let iterator = Iter::from_callbacks(
            move || !has_state.borrow().is_empty(),
            move || next_state.borrow_mut().remove(0),
        );
        let alias = iterator.clone();

        state.borrow_mut()[0] = 9;

        assert!(alias.has_next());
        assert_eq!(iterator.next(), 9);
        assert!(!alias.has_next());
    }

    #[test]
    fn key_value_records_preserve_shared_alias_mutation() {
        let record = key_value(String::from("before"), 1_i32);
        let alias = record.clone();

        alias.borrow_mut().set("key", String::from("after"));
        alias.borrow_mut().set("value", 2_i32);

        assert!(record.ptr_eq(&alias));
        assert_eq!(record.borrow().get::<String>("key"), "after");
        assert_eq!(record.borrow().get::<i32>("value"), 2);
    }
}
