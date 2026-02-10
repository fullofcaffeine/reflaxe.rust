use crate::cell::{HxCell, HxRc, HxRef};
use std::iter::Peekable;

#[derive(Clone, Debug)]
pub struct KeyValue<K, V> {
    pub key: K,
    pub value: V,
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
            iter: HxRc::new(HxCell::new(vec.into_iter().peekable())),
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
