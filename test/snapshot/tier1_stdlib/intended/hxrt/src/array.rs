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

    pub fn concat(&self, other: Array<T>) -> Array<T>
    where
        T: Clone,
    {
        let mut out = self.inner.borrow().clone();
        out.extend(other.inner.borrow().iter().cloned());
        Array::from_vec(out)
    }

    pub fn copy(&self) -> Array<T>
    where
        T: Clone,
    {
        Array::from_vec(self.inner.borrow().clone())
    }

    pub fn reverse(&self) {
        self.inner.borrow_mut().reverse();
    }

    pub fn shift(&self) -> Option<T> {
        let mut inner = self.inner.borrow_mut();
        if inner.is_empty() {
            None
        } else {
            Some(inner.remove(0))
        }
    }

    pub fn unshift(&self, value: T) {
        self.inner.borrow_mut().insert(0, value);
    }

    pub fn insert(&self, pos: i32, value: T) {
        let mut inner = self.inner.borrow_mut();
        let len = inner.len() as i32;
        let pos = pos.clamp(0, len) as usize;
        inner.insert(pos, value);
    }

    pub fn slice(&self, pos: i32, end: Option<i32>) -> Array<T>
    where
        T: Clone,
    {
        let inner = self.inner.borrow();
        let len = inner.len() as i32;
        let mut start = pos;
        if start < 0 {
            start += len;
        }
        start = start.clamp(0, len);

        let mut end = end.unwrap_or(len);
        if end < 0 {
            end += len;
        }
        end = end.clamp(0, len);

        if end < start {
            end = start;
        }

        Array::from_vec(inner[start as usize..end as usize].to_vec())
    }

    pub fn splice(&self, pos: i32, len: i32) -> Array<T> {
        let mut inner = self.inner.borrow_mut();
        let total = inner.len() as i32;

        let mut pos = pos;
        if pos < 0 {
            pos += total;
        }
        pos = pos.clamp(0, total);

        let len = len.max(0);
        let end = (pos + len).min(total);

        let removed: Vec<T> = inner.drain(pos as usize..end as usize).collect();
        Array::from_vec(removed)
    }

    pub fn resize(&self, len: i32)
    where
        T: Default,
    {
        let mut inner = self.inner.borrow_mut();
        let len = len.max(0) as usize;
        inner.resize_with(len, T::default);
    }

    pub fn contains(&self, value: T) -> bool
    where
        T: PartialEq,
    {
        self.inner.borrow().contains(&value)
    }

    pub fn remove(&self, value: T) -> bool
    where
        T: PartialEq,
    {
        let mut inner = self.inner.borrow_mut();
        if let Some(pos) = inner.iter().position(|x| *x == value) {
            inner.remove(pos);
            true
        } else {
            false
        }
    }

    pub fn index_of(&self, value: T, from_index: Option<i32>) -> i32
    where
        T: PartialEq,
    {
        let inner = self.inner.borrow();
        let len = inner.len() as i32;
        if len == 0 {
            return -1;
        }

        let mut start = from_index.unwrap_or(0);
        if start < 0 {
            start += len;
        }
        start = start.clamp(0, len);

        for i in start..len {
            if inner[i as usize] == value {
                return i;
            }
        }
        -1
    }

    // Keep Haxe-style names for cases where codegen preserves them (e.g. `indexOf`).
    #[allow(non_snake_case)]
    pub fn indexOf(&self, value: T, from_index: Option<i32>) -> i32
    where
        T: PartialEq,
    {
        self.index_of(value, from_index)
    }

    pub fn last_index_of(&self, value: T, from_index: Option<i32>) -> i32
    where
        T: PartialEq,
    {
        let inner = self.inner.borrow();
        let len = inner.len() as i32;
        if len == 0 {
            return -1;
        }

        let mut start = from_index.unwrap_or(len - 1);
        if start < 0 {
            start += len;
        }
        start = start.clamp(0, len - 1);

        let mut i = start;
        loop {
            if inner[i as usize] == value {
                return i;
            }
            if i == 0 {
                break;
            }
            i -= 1;
        }
        -1
    }

    // Keep Haxe-style names for cases where codegen preserves them (e.g. `lastIndexOf`).
    #[allow(non_snake_case)]
    pub fn lastIndexOf(&self, value: T, from_index: Option<i32>) -> i32
    where
        T: PartialEq,
    {
        self.last_index_of(value, from_index)
    }

    pub fn sort(&self, compare: Rc<dyn Fn(T, T) -> i32>)
    where
        T: Clone,
    {
        let mut inner = self.inner.borrow_mut();
        inner.sort_by(|a, b| {
            let r = compare(a.clone(), b.clone());
            if r < 0 {
                std::cmp::Ordering::Less
            } else if r > 0 {
                std::cmp::Ordering::Greater
            } else {
                std::cmp::Ordering::Equal
            }
        });
    }

    pub fn join(&self, sep: String) -> String
    where
        T: ToString,
    {
        self.inner
            .borrow()
            .iter()
            .map(|x| x.to_string())
            .collect::<Vec<_>>()
            .join(sep.as_str())
    }
}
