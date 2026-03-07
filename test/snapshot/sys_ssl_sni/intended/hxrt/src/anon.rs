use crate::array::Array;
use crate::cell::HxRef;
use crate::dynamic::Dynamic;
use std::any::Any;
use std::collections::BTreeMap;

/// `hxrt::anon::Anon`
///
/// Runtime representation for Haxe anonymous objects / structural records.
///
/// Why
/// - Haxe anonymous objects (record literals) are mutable reference values:
///   - assignment aliases: `var b = a; b.x = 1` mutates `a`
///   - passing aliases
/// - Rust has no native structural record type, so we need a small runtime container.
///
/// What
/// - A string-keyed map from field name to `Dynamic`.
/// - Intended for compiler-generated code only (not a public ergonomic API).
///
/// How
/// - The compiler lowers object literals into a `HxRef<Anon>` (a shared, interior-mutable reference).
/// - Field reads/writes are compiled into `borrow().get::<T>(...)` / `borrow_mut().set(...)`.
/// - For v1 stdlib parity, we also support runtime string keys (Reflect/JSON use-cases).
#[derive(Clone, Debug, Default)]
pub struct Anon {
    fields: BTreeMap<String, Dynamic>,
}

impl Anon {
    #[inline]
    pub fn new() -> Self {
        Self {
            fields: BTreeMap::new(),
        }
    }

    #[inline]
    pub fn set<T>(&mut self, key: &str, value: T)
    where
        T: Any + Clone + Send + Sync + 'static,
    {
        self.fields.insert(key.to_string(), Dynamic::from(value));
    }

    #[inline]
    pub fn get<T>(&self, key: &str) -> T
    where
        T: Any + Clone + Send + Sync + 'static,
    {
        let v = self
            .fields
            .get(key)
            .unwrap_or_else(|| panic!("missing anon field: {}", key));
        v.downcast_ref::<T>()
            .unwrap_or_else(|| panic!("anon field has wrong type: {}", key))
            .clone()
    }

    #[inline]
    pub fn get_dyn(&self, key: &str) -> Dynamic {
        self.fields.get(key).cloned().unwrap_or_else(Dynamic::null)
    }

    #[inline]
    pub fn set_dyn(&mut self, key: &str, value: Dynamic) {
        self.fields.insert(key.to_string(), value);
    }

    #[inline]
    pub fn has_key(&self, key: &str) -> bool {
        self.fields.contains_key(key)
    }

    #[inline]
    pub fn keys(&self) -> Array<String> {
        Array::from_vec(self.fields.keys().cloned().collect())
    }
}

#[inline]
pub fn anon_get(obj: &HxRef<Anon>, key: &str) -> Dynamic {
    obj.borrow().get_dyn(key)
}

#[inline]
pub fn anon_set(obj: &HxRef<Anon>, key: &str, value: Dynamic) {
    obj.borrow_mut().set_dyn(key, value)
}

#[inline]
pub fn anon_has(obj: &HxRef<Anon>, key: &str) -> bool {
    obj.borrow().has_key(key)
}

#[inline]
pub fn anon_keys(obj: &HxRef<Anon>) -> Array<String> {
    obj.borrow().keys()
}

/// Return a cloned list of `(key, value)` entries for an `Anon` object.
///
/// This is intentionally cloning: `Anon` is stored behind interior mutability, and callers
/// (JSON, reflection helpers) should not hold borrows across arbitrary code.
#[inline]
pub fn anon_entries(obj: &HxRef<Anon>) -> Vec<(String, Dynamic)> {
    obj.borrow()
        .fields
        .iter()
        .map(|(k, v)| (k.clone(), v.clone()))
        .collect()
}
