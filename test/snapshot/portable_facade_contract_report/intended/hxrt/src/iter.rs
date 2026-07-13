use crate::anon::Anon;
use crate::cell::HxRef;
use std::any::Any;
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
/// - Owns an iterator over `T` and exposes `has_next()` / `next()` as `&self` methods,
///   using interior mutability.
///
/// How
/// - Constructed from a `Vec<T>` (so we avoid boxing trait objects for now).
/// - `has_next()` peeks without consuming.
/// - `next()` consumes and panics if called when exhausted (matches Haxe's "unspecified behavior").
#[derive(Debug)]
pub struct Iter<T> {
    iter: HxRef<Peekable<std::vec::IntoIter<T>>>,
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
            iter: HxRef::new(vec.into_iter().peekable()),
        }
    }

    pub fn has_next(&self) -> bool {
        self.iter.borrow_mut().peek().is_some()
    }

    #[allow(non_snake_case)]
    pub fn hasNext(&self) -> bool {
        self.has_next()
    }

    pub fn next(&self) -> T {
        self.iter
            .borrow_mut()
            .next()
            .expect("hxrt::iter::Iter.next() called when exhausted")
    }
}

#[cfg(test)]
mod tests {
    use super::key_value;

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
