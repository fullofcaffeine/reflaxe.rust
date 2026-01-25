use std::cell::RefCell;
use std::rc::Rc;

/// `hxrt::array::Array<T>`
///
/// Shared, mutable array storage matching Haxe `Array<T>` semantics.
///
/// Why
/// - In Haxe, `Array<T>` is a **mutable reference type**:
///   - assignment aliases (`var b = a; b.push(x)` mutates `a`)
///   - passing to functions aliases
///   - values remain usable after calls (no Rust-style moves)
/// - A plain Rust `Vec<T>` is an owned value that moves by default, and does not alias on assignment.
///
/// What
/// - A lightweight wrapper around `Rc<RefCell<Vec<T>>>`.
/// - Cloning an `Array<T>` is cheap (it clones the `Rc`, not the underlying elements).
///
/// How
/// - Mutation is performed through interior mutability (`RefCell`), so methods can take `&self`.
/// - Indexing helpers return owned `T` values by cloning, which aligns with how the backend models
///   Haxe "reusable values" semantics.
#[derive(Clone, Debug, Default)]
pub struct Array<T> {
    inner: Rc<RefCell<Vec<T>>>,
}

impl<T> Array<T> {
    pub fn new() -> Self {
        Self {
            inner: Rc::new(RefCell::new(Vec::new())),
        }
    }

    pub fn from_vec(vec: Vec<T>) -> Self {
        Self {
            inner: Rc::new(RefCell::new(vec)),
        }
    }

    pub fn to_vec(&self) -> Vec<T>
    where
        T: Clone,
    {
        self.inner.borrow().clone()
    }

    pub fn len(&self) -> usize {
        self.inner.borrow().len()
    }

    pub fn is_empty(&self) -> bool {
        self.inner.borrow().is_empty()
    }

    pub fn push(&self, value: T) -> i32 {
        self.inner.borrow_mut().push(value);
        self.len() as i32
    }

    pub fn pop(&self) -> Option<T> {
        self.inner.borrow_mut().pop()
    }

    pub fn set(&self, index: usize, value: T) {
        self.inner.borrow_mut()[index] = value;
    }

    pub fn get(&self, index: usize) -> Option<T>
    where
        T: Clone,
    {
        self.inner.borrow().get(index).cloned()
    }

    pub fn get_unchecked(&self, index: usize) -> T
    where
        T: Clone,
    {
        self.inner.borrow()[index].clone()
    }

    /// Iterator helper used by codegen for `for (x in array)` loops.
    ///
    /// Returns an owned iterator so the borrow guard does not escape.
    pub fn iter(&self) -> std::vec::IntoIter<T>
    where
        T: Clone,
    {
        self.to_vec().into_iter()
    }
}
