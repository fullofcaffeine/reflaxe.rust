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
/// - Keys are expected to be compile-time literals and typically `'static`.
#[derive(Clone, Debug, Default)]
pub struct Anon {
    fields: BTreeMap<&'static str, Dynamic>,
}

impl Anon {
    #[inline]
    pub fn new() -> Self {
        Self {
            fields: BTreeMap::new(),
        }
    }

    #[inline]
    pub fn set<T>(&mut self, key: &'static str, value: T)
    where
        T: Any + Clone + Send + Sync + 'static,
    {
        self.fields.insert(key, Dynamic::from(value));
    }

    #[inline]
    pub fn get<T>(&self, key: &'static str) -> T
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
}
