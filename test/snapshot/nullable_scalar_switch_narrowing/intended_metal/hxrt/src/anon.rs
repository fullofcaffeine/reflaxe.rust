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
/// - Generated field writes arrive through `set_dyn` after the compiler has explicitly converted the
///   source value to `Dynamic`; typed reads use `get::<T>` and Dynamic reads use `get_dyn`.
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

    /// Stores a concrete value for runtime-internal callers that do not originate at a Haxe source
    /// boundary. Generated Haxe field writes use `set_dyn` so the compiler can validate and report the
    /// exact conversion before Rust is emitted.
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

    /// Stores an already-converted field payload.
    ///
    /// Generated code owns the conversion so borrowed values become owned before storage and typed
    /// fields retain the exact carrier that `get<T>` will request, such as `Option<bool>`.
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

/// Return the current field count for an anonymous-object runtime value.
///
/// Why
/// - JSON serialization wants an accurate map-length hint without first cloning all entries.
///
/// What
/// - Reads the `Anon` field count under a short-lived borrow.
///
/// How
/// - Mirrors `dyn_object_len` so the JSON fast path can treat `Anon` and `DynObject` uniformly.
#[inline]
pub fn anon_len(obj: &HxRef<Anon>) -> usize {
    obj.borrow().fields.len()
}

/// Visit anonymous-object entries under a single read borrow.
///
/// Why
/// - The JSON fast path should serialize anonymous-object fields directly rather than cloning an
///   owned `(String, Dynamic)` list first.
///
/// What
/// - A narrow traversal helper for serialization-style runtime walks.
///
/// How
/// - Holds one read borrow while invoking the callback with borrowed key/value views.
/// - Returns `Result` so serializer callbacks can propagate failures without an intermediate buffer.
#[inline]
pub fn anon_try_for_each_entry<E, F>(obj: &HxRef<Anon>, mut f: F) -> Result<(), E>
where
    F: FnMut(&str, &Dynamic) -> Result<(), E>,
{
    let borrow = obj.borrow();
    for (key, value) in borrow.fields.iter() {
        f(key.as_str(), value)?;
    }
    Ok(())
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
