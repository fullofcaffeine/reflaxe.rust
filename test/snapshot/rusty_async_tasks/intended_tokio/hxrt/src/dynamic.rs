use std::any::Any;
use std::collections::BTreeMap;

use crate::array::Array;
use crate::cell::HxRef;
use crate::exception;
use crate::hxref;

pub trait AnyClone: Any + Send + Sync {
    fn clone_box(&self) -> Box<dyn AnyClone>;
    fn as_any(&self) -> &dyn Any;
}

impl<T> AnyClone for T
where
    T: Any + Clone + Send + Sync + 'static,
{
    #[inline]
    fn clone_box(&self) -> Box<dyn AnyClone> {
        Box::new(self.clone())
    }

    #[inline]
    fn as_any(&self) -> &dyn Any {
        self
    }
}

impl Clone for Box<dyn AnyClone> {
    #[inline]
    fn clone(&self) -> Self {
        (**self).clone_box()
    }
}

/// Haxe-style dynamic value.
///
/// This is intentionally small but **semantics-focused**:
///
/// Why
/// - Many Haxe APIs accept `Dynamic` (e.g. `Sys.println`, thrown exception payloads).
/// - We need predictable, platform-style stringification (`Std.string`, `trace`, printing).
///
/// What
/// - Stores a boxed `Any` so the runtime can downcast to common primitives/containers.
/// - Provides a Haxe-style stringification method `to_haxe_string()`.
///
/// How
/// - `to_haxe_string()` handles common primitives and a few common `Option<T>` / `Array<T>` cases.
/// - Unknown values fall back to a stable type-name marker (`<Dynamic:...>`), not a pointer address.
/// - Optional `type_id` metadata preserves Haxe class/enum RTTI across unavoidable `Dynamic` boundaries.
pub struct Dynamic(Option<Box<dyn AnyClone>>, &'static str, usize, Option<u32>);

impl Clone for Dynamic {
    #[inline]
    fn clone(&self) -> Self {
        Dynamic(self.0.clone(), self.1, self.2, self.3)
    }
}

impl Default for Dynamic {
    #[inline]
    fn default() -> Self {
        Dynamic::null()
    }
}

impl Dynamic {
    #[inline]
    pub fn null() -> Dynamic {
        Dynamic(None, "null", 0, None)
    }

    #[inline]
    pub fn is_null(&self) -> bool {
        self.0.is_none()
    }

    #[inline]
    pub fn from<T>(value: T) -> Dynamic
    where
        T: Any + Clone + Send + Sync + 'static,
    {
        Dynamic(Some(Box::new(value)), std::any::type_name::<T>(), 0, None)
    }

    #[inline]
    pub fn from_ref<T>(value: T) -> Dynamic
    where
        T: hxref::HxRefLike + Any + Clone + Send + Sync + 'static,
    {
        let ptr = value.ptr_usize();
        Dynamic(Some(Box::new(value)), std::any::type_name::<T>(), ptr, None)
    }

    /// Box a value into `Dynamic` while attaching a stable target-level type id.
    ///
    /// Why
    /// - `Std.isOfType(value:Dynamic, SomeClass)` needs runtime type checks for class/enum values.
    /// - A plain Rust `Any` downcast is not enough for subtype checks.
    ///
    /// What
    /// - Stores the same payload as `from(...)`, plus `Some(type_id)`.
    ///
    /// How
    /// - The compiler computes stable ids and passes them at the dynamic boundary.
    #[inline]
    pub fn from_with_type_id<T>(value: T, type_id: u32) -> Dynamic
    where
        T: Any + Clone + Send + Sync + 'static,
    {
        Dynamic(
            Some(Box::new(value)),
            std::any::type_name::<T>(),
            0,
            Some(type_id),
        )
    }

    /// Reference-style `Dynamic` boxing variant with attached stable type id metadata.
    ///
    /// Why
    /// - Class instances are represented as shared references (`HxRef` / `HxRc`) and must retain:
    ///   - pointer identity (for `Dynamic` equality semantics),
    ///   - runtime type id (for `Std.isOfType` subtype checks through `Dynamic`).
    ///
    /// What
    /// - Equivalent to `from_ref(...)`, with `Some(type_id)` metadata.
    ///
    /// How
    /// - Stores pointer identity via `HxRefLike::ptr_usize()`.
    /// - Stores compiler-provided type id metadata in the dynamic header.
    #[inline]
    pub fn from_ref_with_type_id<T>(value: T, type_id: u32) -> Dynamic
    where
        T: hxref::HxRefLike + Any + Clone + Send + Sync + 'static,
    {
        let ptr = value.ptr_usize();
        Dynamic(
            Some(Box::new(value)),
            std::any::type_name::<T>(),
            ptr,
            Some(type_id),
        )
    }

    /// Pointer identity for Haxe reference-like values boxed into `Dynamic`.
    ///
    /// This is `0` for:
    /// - `null`
    /// - non-reference values boxed via `Dynamic::from`
    #[inline]
    pub fn ptr_usize(&self) -> usize {
        self.2
    }

    /// Return optional stable runtime type-id metadata carried across dynamic boundaries.
    ///
    /// Why
    /// - `Std.isOfType` on `Dynamic` class/enum values needs backend-stable ids at runtime.
    ///
    /// What
    /// - `Some(id)` when the compiler boxed the value through `*_with_type_id`.
    /// - `None` for payloads that do not carry class/enum RTTI metadata.
    #[inline]
    pub fn type_id(&self) -> Option<u32> {
        self.3
    }

    pub fn to_haxe_string(&self) -> String {
        if self.0.is_none() {
            return String::from("null");
        }

        if let Some(v) = self.downcast_ref::<crate::string::HxString>() {
            return v.to_haxe_string();
        }
        if let Some(v) = self.downcast_ref::<String>() {
            return v.clone();
        }
        if let Some(v) = self.downcast_ref::<i32>() {
            return v.to_string();
        }
        if let Some(v) = self.downcast_ref::<f64>() {
            return v.to_string();
        }
        if let Some(v) = self.downcast_ref::<bool>() {
            return v.to_string();
        }

        // Common `Null<T>` representations (lowered to `Option<T>`).
        if let Some(v) = self.downcast_ref::<Option<i32>>() {
            return match v {
                Some(x) => x.to_string(),
                None => String::from("null"),
            };
        }
        if let Some(v) = self.downcast_ref::<Option<f64>>() {
            return match v {
                Some(x) => x.to_string(),
                None => String::from("null"),
            };
        }
        if let Some(v) = self.downcast_ref::<Option<bool>>() {
            return match v {
                Some(x) => x.to_string(),
                None => String::from("null"),
            };
        }
        if let Some(v) = self.downcast_ref::<Option<String>>() {
            return match v {
                Some(x) => x.clone(),
                None => String::from("null"),
            };
        }

        // Common `Array<T>` instantiations (kept concrete so we can downcast).
        if let Some(v) = self.downcast_ref::<crate::array::Array<i32>>() {
            return v.toString();
        }
        if let Some(v) = self.downcast_ref::<crate::array::Array<f64>>() {
            return v.toString();
        }
        if let Some(v) = self.downcast_ref::<crate::array::Array<bool>>() {
            return v.toString();
        }
        if let Some(v) = self.downcast_ref::<crate::array::Array<String>>() {
            return v.toString();
        }

        if let Some(v) = self.downcast_ref::<crate::io::Error>() {
            return v.to_haxe_string();
        }

        format!("<Dynamic:{}>", self.1)
    }

    #[inline]
    pub fn downcast_ref<T: Any + 'static>(&self) -> Option<&T> {
        let any = self.0.as_ref()?.as_ref().as_any();
        any.downcast_ref::<T>()
    }

    #[inline]
    pub fn downcast<T: Any + Clone + 'static>(self) -> Result<Box<T>, Dynamic> {
        match self.0 {
            None => Err(self),
            Some(b) => {
                let any = b.as_ref().as_any();
                if let Some(v) = any.downcast_ref::<T>() {
                    Ok(Box::new(v.clone()))
                } else {
                    Err(Dynamic(Some(b), self.1, self.2, self.3))
                }
            }
        }
    }
}

impl hxref::HxRefLike for Dynamic {
    fn ptr_usize(&self) -> usize {
        self.2
    }
}

impl std::fmt::Debug for Dynamic {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.to_haxe_string())
    }
}

impl std::fmt::Display for Dynamic {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.to_haxe_string())
    }
}

#[inline]
pub fn from<T>(value: T) -> Dynamic
where
    T: Any + Clone + Send + Sync + 'static,
{
    Dynamic::from(value)
}

#[inline]
pub fn from_ref<T>(value: T) -> Dynamic
where
    T: hxref::HxRefLike + Any + Clone + Send + Sync + 'static,
{
    Dynamic::from_ref(value)
}

#[inline]
pub fn from_with_type_id<T>(value: T, type_id: u32) -> Dynamic
where
    T: Any + Clone + Send + Sync + 'static,
{
    Dynamic::from_with_type_id(value, type_id)
}

#[inline]
pub fn from_ref_with_type_id<T>(value: T, type_id: u32) -> Dynamic
where
    T: hxref::HxRefLike + Any + Clone + Send + Sync + 'static,
{
    Dynamic::from_ref_with_type_id(value, type_id)
}

/// Runtime-backed "dynamic object" with string keys.
///
/// Why
/// - Haxe `Dynamic` values support field reads/writes at runtime (`obj.field` when `obj:Dynamic`).
/// - Some sys APIs (notably `sys.db.ResultSet.next()`) return dynamic rows whose column names are
///   only known at runtime.
///
/// What
/// - A mutable, string-keyed map `String -> Dynamic`.
/// - Stored behind `HxRef` so assignment/aliasing semantics match Haxe objects.
///
/// How
/// - `sys.db` builds row objects as `HxRef<DynObject>` and boxes them into `Dynamic`.
/// - The compiler lowers `TField(_, FDynamic(name))` into `hxrt::dynamic::field_get/field_set`.
#[derive(Clone, Debug, Default)]
pub struct DynObject {
    fields: BTreeMap<String, Dynamic>,
}

impl DynObject {
    #[inline]
    pub fn new() -> Self {
        Self {
            fields: BTreeMap::new(),
        }
    }

    #[inline]
    pub fn keys(&self) -> Array<String> {
        Array::from_vec(self.fields.keys().cloned().collect())
    }
}

#[inline]
pub fn dyn_object_new() -> HxRef<DynObject> {
    HxRef::new(DynObject::new())
}

#[inline]
pub fn dyn_object_set(obj: &HxRef<DynObject>, key: &str, value: Dynamic) {
    obj.borrow_mut().fields.insert(key.to_string(), value);
}

#[inline]
pub fn dyn_object_get(obj: &HxRef<DynObject>, key: &str) -> Dynamic {
    obj.borrow()
        .fields
        .get(key)
        .cloned()
        .unwrap_or_else(Dynamic::null)
}

#[inline]
fn map_string_array<S>(values: Array<String>) -> Array<S>
where
    S: From<String> + Clone,
{
    Array::from_vec(values.to_vec().into_iter().map(S::from).collect())
}

#[inline]
pub fn dyn_object_keys<S>(obj: &HxRef<DynObject>) -> Array<S>
where
    S: From<String> + Clone,
{
    map_string_array(obj.borrow().keys())
}

/// Return a cloned list of `(key, value)` entries for a `DynObject`.
///
/// This is intentionally cloning: `DynObject` is stored behind interior mutability, and callers
/// (JSON, reflection helpers) should not hold borrows across arbitrary code.
#[inline]
pub fn dyn_object_entries(obj: &HxRef<DynObject>) -> Vec<(String, Dynamic)> {
    obj.borrow()
        .fields
        .iter()
        .map(|(k, v)| (k.clone(), v.clone()))
        .collect()
}

/// Return field names for a `Dynamic` receiver when it is a dynamic object.
///
/// Semantics:
/// - If `obj` is a boxed `HxRef<DynObject>`: returns its keys.
/// - If `obj` is a boxed `HxRef<anon::Anon>`: returns its keys.
/// - Otherwise: returns an empty array.
#[inline]
pub fn field_names<S>(obj: &Dynamic) -> Array<S>
where
    S: From<String> + Clone,
{
    if let Some(o) = obj.downcast_ref::<HxRef<DynObject>>() {
        return dyn_object_keys(o);
    }
    if let Some(a) = obj.downcast_ref::<crate::cell::HxRef<crate::anon::Anon>>() {
        return map_string_array(crate::anon::anon_keys(a));
    }
    Array::<S>::new()
}

/// Read a dynamic field from a `Dynamic` receiver.
///
/// Semantics:
/// - If `obj` is a boxed `HxRef<DynObject>`: returns the field value or `null` if missing.
/// - Otherwise: returns `null`.
#[inline]
pub fn field_get(obj: &Dynamic, key: &str) -> Dynamic {
    if let Some(o) = obj.downcast_ref::<HxRef<DynObject>>() {
        return dyn_object_get(o, key);
    }
    if let Some(a) = obj.downcast_ref::<crate::cell::HxRef<crate::anon::Anon>>() {
        return crate::anon::anon_get(a, key);
    }
    Dynamic::null()
}

/// Write a dynamic field into a `Dynamic` receiver.
///
/// Semantics:
/// - If `obj` is a boxed `HxRef<DynObject>`: sets the field value.
/// - Otherwise: throws (mirrors other targets where setting on non-object is an error).
#[inline]
pub fn field_set(obj: &Dynamic, key: &str, value: Dynamic) {
    if let Some(o) = obj.downcast_ref::<HxRef<DynObject>>() {
        dyn_object_set(o, key, value);
        return;
    }
    if let Some(a) = obj.downcast_ref::<crate::cell::HxRef<crate::anon::Anon>>() {
        crate::anon::anon_set(a, key, value);
        return;
    }
    exception::throw(Dynamic::from(format!(
        "Dynamic field write on unsupported receiver (field: {key})"
    )));
}

/// Haxe-style equality for `Dynamic`.
///
/// Why
/// - Haxe allows comparing `Dynamic` values with `==` / `!=`.
/// - The serializer cache (`haxe.Serializer.serializeRef`) relies on `Dynamic` equality to detect
///   repeated references.
///
/// What
/// - Compares common primitives by value.
/// - Compares common reference-like values (arrays, anon objects, dyn objects, bytes) by identity.
///
/// How
/// - Uses `downcast_ref` for concrete cases.
/// - Falls back to `false` for unknown/unsupported dynamic payloads.
#[inline]
pub fn eq(a: &Dynamic, b: &Dynamic) -> bool {
    if a.is_null() && b.is_null() {
        return true;
    }
    if a.is_null() || b.is_null() {
        return false;
    }

    if let (Some(x), Some(y)) = (a.downcast_ref::<i32>(), b.downcast_ref::<i32>()) {
        return x == y;
    }
    if let (Some(x), Some(y)) = (a.downcast_ref::<f64>(), b.downcast_ref::<f64>()) {
        return x == y;
    }
    if let (Some(x), Some(y)) = (a.downcast_ref::<bool>(), b.downcast_ref::<bool>()) {
        return x == y;
    }
    if let (Some(x), Some(y)) = (a.downcast_ref::<String>(), b.downcast_ref::<String>()) {
        return x == y;
    }
    if let (Some(x), Some(y)) = (
        a.downcast_ref::<crate::string::HxString>(),
        b.downcast_ref::<crate::string::HxString>(),
    ) {
        return x.to_haxe_string() == y.to_haxe_string();
    }

    // Reference-like values (arrays, objects, bytes, etc.) are identity-equal in Haxe.
    // When boxed via `Dynamic::from_ref`, we can compare their stored pointer identities.
    if a.ptr_usize() != 0 && b.ptr_usize() != 0 {
        return a.ptr_usize() == b.ptr_usize();
    }

    false
}

/// Dynamic indexing helper for numeric indices (`obj[index]` where `obj:Dynamic` and `index:Int`).
///
/// Haxe semantics:
/// - Out-of-bounds and negative indices return `null` (not a panic).
#[inline]
pub fn index_get_i32(obj: &Dynamic, index: i32) -> Dynamic {
    if obj.is_null() || index < 0 {
        return Dynamic::null();
    }
    let idx = index as usize;

    if let Some(a) = obj.downcast_ref::<crate::array::Array<Dynamic>>() {
        return a.get(idx).unwrap_or_else(Dynamic::null);
    }
    if let Some(a) = obj.downcast_ref::<crate::array::Array<i32>>() {
        return a.get(idx).map(Dynamic::from).unwrap_or_else(Dynamic::null);
    }
    if let Some(a) = obj.downcast_ref::<crate::array::Array<f64>>() {
        return a.get(idx).map(Dynamic::from).unwrap_or_else(Dynamic::null);
    }
    if let Some(a) = obj.downcast_ref::<crate::array::Array<bool>>() {
        return a.get(idx).map(Dynamic::from).unwrap_or_else(Dynamic::null);
    }
    if let Some(a) = obj.downcast_ref::<crate::array::Array<String>>() {
        return a.get(idx).map(Dynamic::from).unwrap_or_else(Dynamic::null);
    }

    Dynamic::null()
}

/// Dynamic indexing helper for string keys (`obj["field"]` where `obj:Dynamic` and `field:String`).
///
/// Notes
/// - This is used by some upstream std code as a low-level "field get" on `Dynamic`.
/// - For arrays, this handles `"length"` specially.
#[inline]
pub fn index_get_str(obj: &Dynamic, key: &str) -> Dynamic {
    if obj.is_null() {
        return Dynamic::null();
    }

    if key == "length" {
        if let Some(a) = obj.downcast_ref::<crate::array::Array<Dynamic>>() {
            return Dynamic::from(a.len() as i32);
        }
        if let Some(a) = obj.downcast_ref::<crate::array::Array<i32>>() {
            return Dynamic::from(a.len() as i32);
        }
        if let Some(a) = obj.downcast_ref::<crate::array::Array<f64>>() {
            return Dynamic::from(a.len() as i32);
        }
        if let Some(a) = obj.downcast_ref::<crate::array::Array<bool>>() {
            return Dynamic::from(a.len() as i32);
        }
        if let Some(a) = obj.downcast_ref::<crate::array::Array<String>>() {
            return Dynamic::from(a.len() as i32);
        }
    }

    field_get(obj, key)
}

/// Dynamic indexing helper when the index expression itself is dynamic.
#[inline]
pub fn index_get_dyn(obj: &Dynamic, index: &Dynamic) -> Dynamic {
    if let Some(i) = index.downcast_ref::<i32>() {
        return index_get_i32(obj, *i);
    }
    if let Some(s) = index.downcast_ref::<String>() {
        return index_get_str(obj, s.as_str());
    }
    if let Some(s) = index.downcast_ref::<crate::string::HxString>() {
        return index_get_str(obj, s.as_str());
    }
    Dynamic::null()
}

#[cfg(test)]
mod tests {
    use crate::array::Array;
    use crate::cell::HxRef;

    use super::Dynamic;
    use super::{eq, index_get_i32};

    #[test]
    fn downcast_and_to_haxe_string_work() {
        let d = Dynamic::from(String::from("hi"));
        let any = d.0.as_ref().unwrap().as_any();
        assert!(any.is::<String>(), "expected Any to be String");
        assert_eq!(any.downcast_ref::<String>().unwrap().as_str(), "hi");
        assert_eq!(
            d.0.as_ref()
                .unwrap()
                .as_any()
                .downcast_ref::<String>()
                .unwrap()
                .as_str(),
            "hi"
        );
        assert_eq!(d.downcast_ref::<String>().unwrap().as_str(), "hi");
        assert_eq!(d.to_haxe_string(), "hi");

        let d2 = Dynamic::from(123i32);
        assert_eq!(d2.to_haxe_string(), "123");

        let dn = Dynamic::null();
        assert_eq!(dn.to_haxe_string(), "null");
    }

    #[test]
    fn owned_downcast_works() {
        let d = Dynamic::from(String::from("boom"));
        assert!(
            d.downcast_ref::<String>().is_some(),
            "downcast_ref should see String"
        );
        assert!(
            d.0.as_ref().unwrap().as_any().is::<String>(),
            "as_any().is::<String>() should be true"
        );
        let s = d
            .downcast::<String>()
            .expect("downcast String should succeed");
        assert_eq!(s.as_str(), "boom");

        let d2 = Dynamic::from(123i32);
        assert!(
            d2.downcast::<String>().is_err(),
            "downcast wrong type should fail"
        );
    }

    #[test]
    fn owned_downcast_on_null_fails() {
        let dn = Dynamic::null();
        assert!(
            dn.downcast::<String>().is_err(),
            "downcast on null should fail"
        );
    }

    #[test]
    fn dynamic_eq_primitives_work() {
        assert!(eq(&Dynamic::null(), &Dynamic::null()));
        assert!(!eq(&Dynamic::null(), &Dynamic::from(1i32)));
        assert!(eq(&Dynamic::from(1i32), &Dynamic::from(1i32)));
        assert!(!eq(&Dynamic::from(1i32), &Dynamic::from(2i32)));
        assert!(eq(
            &Dynamic::from(String::from("x")),
            &Dynamic::from(String::from("x"))
        ));
    }

    #[test]
    fn dynamic_eq_array_identity_works() {
        let a = Array::<Dynamic>::new();
        a.push(Dynamic::from(1i32));
        let b = a.clone();
        assert!(eq(&Dynamic::from_ref(a), &Dynamic::from_ref(b)));
    }

    #[test]
    fn dynamic_eq_hxref_identity_works_for_dyn_object() {
        let o = HxRef::new(super::DynObject::new());
        let d1 = Dynamic::from_ref(o.clone());
        let d2 = Dynamic::from_ref(o);
        assert!(eq(&d1, &d2));
    }

    #[test]
    fn dynamic_index_get_on_dynamic_array_works() {
        let a = Array::<Dynamic>::new();
        a.push(Dynamic::from(1i32));
        a.push(Dynamic::from(2i32));
        let d = Dynamic::from(a);
        assert_eq!(
            index_get_i32(&d, 0).downcast_ref::<i32>().unwrap().clone(),
            1
        );
        assert_eq!(
            index_get_i32(&d, 1).downcast_ref::<i32>().unwrap().clone(),
            2
        );
        assert!(index_get_i32(&d, 999).is_null());
        assert!(index_get_i32(&d, -1).is_null());
    }

    #[test]
    fn dynamic_type_id_metadata_roundtrips() {
        let tagged = Dynamic::from_with_type_id(7i32, 0x1234_abcd);
        assert_eq!(tagged.type_id(), Some(0x1234_abcd));
        assert_eq!(tagged.clone().type_id(), Some(0x1234_abcd));

        let plain = Dynamic::from(7i32);
        assert_eq!(plain.type_id(), None);

        let obj = HxRef::new(super::DynObject::new());
        let tagged_ref = Dynamic::from_ref_with_type_id(obj.clone(), 0xabcd_9876);
        assert_eq!(tagged_ref.type_id(), Some(0xabcd_9876));
        assert!(tagged_ref.ptr_usize() != 0);
        assert_eq!(tagged_ref.ptr_usize(), Dynamic::from_ref(obj).ptr_usize());
    }
}
