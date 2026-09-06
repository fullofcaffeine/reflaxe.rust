use crate::anon::Anon;
use crate::array::Array;
use crate::cell::{HxDynRef, HxRef};
use crate::dynamic::{DynObject, Dynamic};
use crate::exception;
use crate::string::HxString;
use serde::de::{Deserialize, Deserializer, MapAccess, SeqAccess, Visitor};
use serde::ser::{Serialize, SerializeMap, SerializeSeq, Serializer};
use serde_json::Value;
use std::fmt;

fn throw_json(msg: String) -> ! {
    exception::throw(Dynamic::from(msg))
}

const VALUE_KIND_NULL: i32 = 0;
const VALUE_KIND_BOOL: i32 = 1;
const VALUE_KIND_INT: i32 = 2;
const VALUE_KIND_FLOAT: i32 = 3;
const VALUE_KIND_STRING: i32 = 4;
const VALUE_KIND_ARRAY: i32 = 5;
const VALUE_KIND_OBJECT: i32 = 6;

fn dynamic_json_number_kind(v: &Dynamic) -> Option<i32> {
    if v.downcast_ref::<i32>().is_some() {
        return Some(VALUE_KIND_INT);
    }
    if v.downcast_ref::<f64>().is_some() {
        return Some(VALUE_KIND_FLOAT);
    }
    None
}

/// Borrow a JSON-compatible string payload from a runtime `Dynamic`.
///
/// Why
/// - JSON boundary helpers frequently only need to know whether a dynamic payload is string-like
///   or need a temporary borrowed `&str`.
/// - Cloning into an owned `String` just to check kind tags or feed a serializer is wasted work on
///   the hot path.
///
/// What
/// - A shared borrowed-view helper for runtime JSON string handling.
///
/// How
/// - Accepts both plain Rust `String` and portable `HxString`.
/// - Preserves the current boundary quirk that `HxString(null)` is treated as the empty string in
///   value-kind / value-as-string helper paths, because that behavior is already relied on by the
///   existing JSON boundary tests.
fn dynamic_json_str(v: &Dynamic) -> Option<&str> {
    if let Some(s) = v.downcast_ref::<String>() {
        return Some(s.as_str());
    }
    if let Some(s) = v.downcast_ref::<HxString>() {
        return Some(s.as_deref().unwrap_or(""));
    }
    None
}

/// Materialize a JSON-compatible runtime string as `HxString`.
///
/// Why
/// - Portable Haxe `String` lowers to `HxString` on this backend.
/// - Returning plain Rust `String` from `hxrt::json` forces the generated Haxe layer to wrap the
///   result immediately, which adds avoidable boundary churn and obscures the true JSON hot path.
///
/// What
/// - A small conversion helper used only when the JSON boundary must hand an owned string back to
///   generated Haxe code.
///
/// How
/// - Reuses existing `HxString` values by converting them once into owned `String`.
/// - Keeps the ownership bridge local to `hxrt::json` so helper paths do not clone strings
///   repeatedly just to answer kind checks or extract a value for `parseValue`.
/// - Preserves the current `HxString(null) -> ""` helper behavior for the `value_as_string` path.
fn dynamic_json_owned_string(v: &Dynamic) -> Option<String> {
    if let Some(s) = v.downcast_ref::<HxString>() {
        return Some(match s.as_deref() {
            Some(inner) => inner.to_string(),
            None => String::new(),
        });
    }
    if let Some(s) = v.downcast_ref::<String>() {
        return Some(s.clone());
    }
    None
}

fn replacer_key_dynamic(key: &str) -> Dynamic {
    Dynamic::from(HxString::from(key.to_string()))
}

/// `DynamicJson` serializes runtime `Dynamic` values directly into JSON.
///
/// Why
/// - The original JSON stringify path rebuilt a full `serde_json::Value` tree before encoding it.
/// - That was semantically correct, but it paid for two layers of work on the hot path:
///   1) walking Haxe runtime shapes into `Value`
///   2) walking the `Value` tree again into bytes
/// - The JSON perf benchmark spends most of its time in exactly that boundary.
///
/// What
/// - A small `serde::Serialize` adapter over `&Dynamic`.
/// - Used only for plain stringify paths so we can write JSON bytes directly from runtime shapes.
///
/// How
/// - Preserves the same public JSON contract as `dynamic_to_json_value`.
/// - Keeps all boundary-specific semantics:
///   - `HxString(null)` => JSON `null`
///   - non-finite floats => JSON `null`
///   - objects/arrays stay reflection-compatible runtime shapes
///   - unknown values still fall back to `to_haxe_string()` as a JSON string
/// - Object serialization clones only key/value handles needed per field instead of materializing
///   an entire `serde_json::Value` subtree first.
struct DynamicJson<'a>(&'a Dynamic);

impl Serialize for DynamicJson<'_> {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        let value = self.0;

        if value.is_null() {
            return serializer.serialize_unit();
        }

        if let Some(inner) = value.downcast_ref::<Dynamic>() {
            return DynamicJson(inner).serialize(serializer);
        }

        if let Some(v) = value.downcast_ref::<HxString>() {
            return match v.as_deref() {
                Some(s) => serializer.serialize_str(s),
                None => serializer.serialize_unit(),
            };
        }
        if let Some(v) = value.downcast_ref::<String>() {
            return serializer.serialize_str(v);
        }
        if let Some(v) = value.downcast_ref::<i32>() {
            return serializer.serialize_i32(*v);
        }
        if let Some(v) = value.downcast_ref::<f64>() {
            return if v.is_finite() {
                serializer.serialize_f64(*v)
            } else {
                serializer.serialize_unit()
            };
        }
        if let Some(v) = value.downcast_ref::<bool>() {
            return serializer.serialize_bool(*v);
        }

        if let Some(v) = value.downcast_ref::<Option<i32>>() {
            return match v {
                Some(x) => serializer.serialize_i32(*x),
                None => serializer.serialize_unit(),
            };
        }
        if let Some(v) = value.downcast_ref::<Option<f64>>() {
            return match v {
                Some(x) if x.is_finite() => serializer.serialize_f64(*x),
                Some(_) | None => serializer.serialize_unit(),
            };
        }
        if let Some(v) = value.downcast_ref::<Option<bool>>() {
            return match v {
                Some(x) => serializer.serialize_bool(*x),
                None => serializer.serialize_unit(),
            };
        }
        if let Some(v) = value.downcast_ref::<Option<String>>() {
            return match v {
                Some(x) => serializer.serialize_str(x),
                None => serializer.serialize_unit(),
            };
        }
        if let Some(v) = value.downcast_ref::<Option<HxString>>() {
            return match v {
                Some(x) => match x.as_deref() {
                    Some(s) => serializer.serialize_str(s),
                    None => serializer.serialize_unit(),
                },
                None => serializer.serialize_unit(),
            };
        }

        if let Some(obj) = value.downcast_ref::<HxRef<DynObject>>() {
            let mut map = serializer.serialize_map(Some(crate::dynamic::dyn_object_len(obj)))?;
            crate::dynamic::dyn_object_try_for_each_entry(obj, |key, field_value| {
                map.serialize_entry(key, &DynamicJson(field_value))
            })?;
            return map.end();
        }
        if let Some(obj) = value.downcast_ref::<HxRef<Anon>>() {
            let mut map = serializer.serialize_map(Some(crate::anon::anon_len(obj)))?;
            crate::anon::anon_try_for_each_entry(obj, |key, field_value| {
                map.serialize_entry(key, &DynamicJson(field_value))
            })?;
            return map.end();
        }

        if let Some(arr) = value.downcast_ref::<Array<Dynamic>>() {
            let mut seq = serializer.serialize_seq(Some(arr.len()))?;
            for item in arr.iter_borrowed() {
                seq.serialize_element(&DynamicJson(&item))?;
            }
            return seq.end();
        }
        if let Some(arr) = value.downcast_ref::<Array<i32>>() {
            let mut seq = serializer.serialize_seq(Some(arr.len()))?;
            for item in arr.iter_borrowed() {
                seq.serialize_element(&item)?;
            }
            return seq.end();
        }
        if let Some(arr) = value.downcast_ref::<Array<f64>>() {
            let mut seq = serializer.serialize_seq(Some(arr.len()))?;
            for item in arr.iter_borrowed() {
                if item.is_finite() {
                    seq.serialize_element(&item)?;
                } else {
                    seq.serialize_element(&())?;
                }
            }
            return seq.end();
        }
        if let Some(arr) = value.downcast_ref::<Array<bool>>() {
            let mut seq = serializer.serialize_seq(Some(arr.len()))?;
            for item in arr.iter_borrowed() {
                seq.serialize_element(&item)?;
            }
            return seq.end();
        }
        if let Some(arr) = value.downcast_ref::<Array<String>>() {
            let mut seq = serializer.serialize_seq(Some(arr.len()))?;
            for item in arr.iter_borrowed() {
                seq.serialize_element(&item)?;
            }
            return seq.end();
        }
        if let Some(arr) = value.downcast_ref::<Array<HxString>>() {
            let mut seq = serializer.serialize_seq(Some(arr.len()))?;
            for item in arr.iter_borrowed() {
                match item.as_deref() {
                    Some(s) => seq.serialize_element(s)?,
                    None => seq.serialize_element(&())?,
                }
            }
            return seq.end();
        }
        if let Some(arr) = value.downcast_ref::<Array<HxRef<Anon>>>() {
            let mut seq = serializer.serialize_seq(Some(arr.len()))?;
            for item in arr.iter_borrowed() {
                let item_dynamic = Dynamic::from(item);
                seq.serialize_element(&DynamicJson(&item_dynamic))?;
            }
            return seq.end();
        }
        if let Some(arr) = value.downcast_ref::<Array<HxRef<DynObject>>>() {
            let mut seq = serializer.serialize_seq(Some(arr.len()))?;
            for item in arr.iter_borrowed() {
                let item_dynamic = Dynamic::from(item);
                seq.serialize_element(&DynamicJson(&item_dynamic))?;
            }
            return seq.end();
        }

        serializer.serialize_str(&value.to_haxe_string())
    }
}

/// `ParsedDynamic` deserializes JSON directly into runtime `Dynamic` shapes.
///
/// Why
/// - The old parse path went through `serde_json::Value` first, then rebuilt that tree into
///   `Dynamic` / `DynObject` / `Array<Dynamic>`.
/// - That was a clean bootstrap path, but it doubled the tree-building work on the JSON hot path.
///
/// What
/// - A local deserialization adapter used only by `hxrt::json::parse`.
/// - Produces the same runtime shapes as `json_value_to_dynamic`.
///
/// How
/// - Numbers still follow the same Haxe-target coercion contract:
///   `i32` when integral and in range, otherwise `f64`.
/// - Objects still become `HxRef<DynObject>`.
/// - Arrays still become `Array<Dynamic>`.
/// - The implementation stays local to `hxrt::json` so it does not silently redefine
///   `Dynamic` deserialization semantics elsewhere in the runtime.
struct ParsedDynamic(Dynamic);

struct ParsedDynamicVisitor;

impl ParsedDynamicVisitor {
    fn number_from_i64(value: i64) -> Dynamic {
        if value >= i32::MIN as i64 && value <= i32::MAX as i64 {
            Dynamic::from(value as i32)
        } else {
            Dynamic::from(value as f64)
        }
    }

    fn number_from_u64(value: u64) -> Dynamic {
        if value <= i32::MAX as u64 {
            Dynamic::from(value as i32)
        } else {
            Dynamic::from(value as f64)
        }
    }
}

impl<'de> Visitor<'de> for ParsedDynamicVisitor {
    type Value = ParsedDynamic;

    fn expecting(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("a JSON value compatible with hxrt::json runtime shapes")
    }

    fn visit_unit<E>(self) -> Result<Self::Value, E>
    where
        E: serde::de::Error,
    {
        Ok(ParsedDynamic(Dynamic::null()))
    }

    fn visit_none<E>(self) -> Result<Self::Value, E>
    where
        E: serde::de::Error,
    {
        Ok(ParsedDynamic(Dynamic::null()))
    }

    fn visit_bool<E>(self, value: bool) -> Result<Self::Value, E>
    where
        E: serde::de::Error,
    {
        Ok(ParsedDynamic(Dynamic::from(value)))
    }

    fn visit_i64<E>(self, value: i64) -> Result<Self::Value, E>
    where
        E: serde::de::Error,
    {
        Ok(ParsedDynamic(Self::number_from_i64(value)))
    }

    fn visit_u64<E>(self, value: u64) -> Result<Self::Value, E>
    where
        E: serde::de::Error,
    {
        Ok(ParsedDynamic(Self::number_from_u64(value)))
    }

    fn visit_f64<E>(self, value: f64) -> Result<Self::Value, E>
    where
        E: serde::de::Error,
    {
        Ok(ParsedDynamic(Dynamic::from(value)))
    }

    fn visit_str<E>(self, value: &str) -> Result<Self::Value, E>
    where
        E: serde::de::Error,
    {
        Ok(ParsedDynamic(Dynamic::from(value.to_string())))
    }

    fn visit_string<E>(self, value: String) -> Result<Self::Value, E>
    where
        E: serde::de::Error,
    {
        Ok(ParsedDynamic(Dynamic::from(value)))
    }

    fn visit_seq<A>(self, mut seq: A) -> Result<Self::Value, A::Error>
    where
        A: SeqAccess<'de>,
    {
        let out = Array::<Dynamic>::new();
        while let Some(item) = seq.next_element::<ParsedDynamic>()? {
            out.push(item.0);
        }
        Ok(ParsedDynamic(Dynamic::from(out)))
    }

    fn visit_map<A>(self, mut map: A) -> Result<Self::Value, A::Error>
    where
        A: MapAccess<'de>,
    {
        let out = crate::dynamic::dyn_object_new();
        while let Some((key, value)) = map.next_entry::<String, ParsedDynamic>()? {
            crate::dynamic::dyn_object_set(&out, key.as_str(), value.0);
        }
        Ok(ParsedDynamic(Dynamic::from(out)))
    }
}

impl<'de> Deserialize<'de> for ParsedDynamic {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        deserializer.deserialize_any(ParsedDynamicVisitor)
    }
}

fn json_value_to_dynamic(v: Value) -> Dynamic {
    match v {
        Value::Null => Dynamic::null(),
        Value::Bool(b) => Dynamic::from(b),
        Value::Number(n) => {
            if let Some(i) = n.as_i64() {
                if i >= i32::MIN as i64 && i <= i32::MAX as i64 {
                    return Dynamic::from(i as i32);
                }
                return Dynamic::from(i as f64);
            }
            if let Some(u) = n.as_u64() {
                if u <= i32::MAX as u64 {
                    return Dynamic::from(u as i32);
                }
                return Dynamic::from(u as f64);
            }
            Dynamic::from(n.as_f64().unwrap_or(0.0))
        }
        Value::String(s) => Dynamic::from(s),
        Value::Array(items) => {
            let out = Array::<Dynamic>::new();
            for item in items {
                out.push(json_value_to_dynamic(item));
            }
            Dynamic::from(out)
        }
        Value::Object(map) => {
            let obj: HxRef<DynObject> = crate::dynamic::dyn_object_new();
            for (k, v) in map {
                crate::dynamic::dyn_object_set(&obj, k.as_str(), json_value_to_dynamic(v));
            }
            Dynamic::from(obj)
        }
    }
}

fn dynamic_to_json_value(v: &Dynamic) -> Value {
    if v.is_null() {
        return Value::Null;
    }

    if let Some(inner) = v.downcast_ref::<Dynamic>() {
        return dynamic_to_json_value(inner);
    }

    if let Some(v) = v.downcast_ref::<HxString>() {
        return match v.as_deref() {
            Some(s) => Value::String(s.to_string()),
            None => Value::Null,
        };
    }
    if let Some(v) = v.downcast_ref::<String>() {
        return Value::String(v.clone());
    }
    if let Some(v) = v.downcast_ref::<i32>() {
        return Value::Number(serde_json::Number::from(*v));
    }
    if let Some(v) = v.downcast_ref::<f64>() {
        if let Some(n) = serde_json::Number::from_f64(*v) {
            return Value::Number(n);
        }
        // Match other targets' behavior: JSON cannot encode NaN/Infinity.
        return Value::Null;
    }
    if let Some(v) = v.downcast_ref::<bool>() {
        return Value::Bool(*v);
    }

    // `Null<T>` (Option<T>) values.
    if let Some(v) = v.downcast_ref::<Option<i32>>() {
        return match v {
            Some(x) => Value::Number(serde_json::Number::from(*x)),
            None => Value::Null,
        };
    }
    if let Some(v) = v.downcast_ref::<Option<f64>>() {
        return match v {
            Some(x) => serde_json::Number::from_f64(*x)
                .map(Value::Number)
                .unwrap_or(Value::Null),
            None => Value::Null,
        };
    }
    if let Some(v) = v.downcast_ref::<Option<bool>>() {
        return match v {
            Some(x) => Value::Bool(*x),
            None => Value::Null,
        };
    }
    if let Some(v) = v.downcast_ref::<Option<String>>() {
        return match v {
            Some(x) => Value::String(x.clone()),
            None => Value::Null,
        };
    }
    if let Some(v) = v.downcast_ref::<Option<HxString>>() {
        return match v {
            Some(x) => match x.as_deref() {
                Some(s) => Value::String(s.to_string()),
                None => Value::Null,
            },
            None => Value::Null,
        };
    }

    // Dynamic objects.
    if let Some(obj) = v.downcast_ref::<HxRef<DynObject>>() {
        let mut out = serde_json::Map::new();
        for (k, dv) in crate::dynamic::dyn_object_entries(obj) {
            out.insert(k, dynamic_to_json_value(&dv));
        }
        return Value::Object(out);
    }
    if let Some(obj) = v.downcast_ref::<HxRef<crate::anon::Anon>>() {
        let mut out = serde_json::Map::new();
        for (k, dv) in crate::anon::anon_entries(obj) {
            out.insert(k, dynamic_to_json_value(&dv));
        }
        return Value::Object(out);
    }

    // Arrays.
    if let Some(arr) = v.downcast_ref::<Array<Dynamic>>() {
        return Value::Array(
            arr.to_vec()
                .into_iter()
                .map(|x| dynamic_to_json_value(&x))
                .collect(),
        );
    }
    if let Some(arr) = v.downcast_ref::<Array<i32>>() {
        return Value::Array(
            arr.to_vec()
                .into_iter()
                .map(|x| Value::Number(serde_json::Number::from(x)))
                .collect(),
        );
    }
    if let Some(arr) = v.downcast_ref::<Array<f64>>() {
        return Value::Array(
            arr.to_vec()
                .into_iter()
                .map(|x| {
                    serde_json::Number::from_f64(x)
                        .map(Value::Number)
                        .unwrap_or(Value::Null)
                })
                .collect(),
        );
    }
    if let Some(arr) = v.downcast_ref::<Array<bool>>() {
        return Value::Array(arr.to_vec().into_iter().map(Value::Bool).collect());
    }
    if let Some(arr) = v.downcast_ref::<Array<String>>() {
        return Value::Array(arr.to_vec().into_iter().map(Value::String).collect());
    }
    if let Some(arr) = v.downcast_ref::<Array<HxString>>() {
        return Value::Array(
            arr.to_vec()
                .into_iter()
                .map(|x| match x.as_deref() {
                    Some(s) => Value::String(s.to_string()),
                    None => Value::Null,
                })
                .collect(),
        );
    }
    if let Some(arr) = v.downcast_ref::<Array<HxRef<crate::anon::Anon>>>() {
        return Value::Array(
            arr.to_vec()
                .into_iter()
                .map(|obj| {
                    let mut out = serde_json::Map::new();
                    for (k, dv) in crate::anon::anon_entries(&obj) {
                        out.insert(k, dynamic_to_json_value(&dv));
                    }
                    Value::Object(out)
                })
                .collect(),
        );
    }
    if let Some(arr) = v.downcast_ref::<Array<HxRef<DynObject>>>() {
        return Value::Array(
            arr.to_vec()
                .into_iter()
                .map(|obj| {
                    let mut out = serde_json::Map::new();
                    for (k, dv) in crate::dynamic::dyn_object_entries(&obj) {
                        out.insert(k, dynamic_to_json_value(&dv));
                    }
                    Value::Object(out)
                })
                .collect(),
        );
    }

    // Best-effort fallback: stringify and encode as a JSON string.
    Value::String(v.to_haxe_string())
}

fn apply_json_replacer(
    key: &str,
    value: Dynamic,
    replacer: &dyn Fn(Dynamic, Dynamic) -> Dynamic,
) -> Dynamic {
    let replaced = replacer(replacer_key_dynamic(key), value);

    if let Some(inner) = replaced.downcast_ref::<Dynamic>() {
        return apply_json_replacer(key, inner.clone(), replacer);
    }

    if let Some(obj) = replaced.downcast_ref::<HxRef<DynObject>>() {
        let out = crate::dynamic::dyn_object_new();
        for (field, child) in crate::dynamic::dyn_object_entries(obj) {
            crate::dynamic::dyn_object_set(
                &out,
                field.as_str(),
                apply_json_replacer(field.as_str(), child, replacer),
            );
        }
        return Dynamic::from(out);
    }

    if let Some(obj) = replaced.downcast_ref::<HxRef<Anon>>() {
        let out = HxRef::new(Anon::new());
        for (field, child) in crate::anon::anon_entries(obj) {
            crate::anon::anon_set(
                &out,
                field.as_str(),
                apply_json_replacer(field.as_str(), child, replacer),
            );
        }
        return Dynamic::from(out);
    }

    if let Some(arr) = replaced.downcast_ref::<Array<Dynamic>>() {
        let out = Array::<Dynamic>::new();
        for (index, child) in arr.to_vec().into_iter().enumerate() {
            out.push(apply_json_replacer(
                index.to_string().as_str(),
                child,
                replacer,
            ));
        }
        return Dynamic::from(out);
    }

    replaced
}

/// Parse a JSON string into Haxe `Dynamic` values.
///
/// Semantics (target baseline):
/// - JSON objects => `HxRef<hxrt::dynamic::DynObject>` boxed into `Dynamic`
/// - JSON arrays => `hxrt::array::Array<Dynamic>` boxed into `Dynamic`
/// - numbers => `i32` when integral and in range, otherwise `f64`
/// - invalid JSON => throws a catchable Haxe exception payload (`String`)
pub fn parse(text: &str) -> Dynamic {
    match serde_json::from_str::<ParsedDynamic>(text) {
        Ok(v) => v.0,
        Err(e) => throw_json(format!("Invalid JSON: {e}")),
    }
}

/// Encode a runtime JSON value into owned JSON text.
///
/// Why
/// - `serde_json` emits owned UTF-8 text.
/// - The Rust backend still has two public string representations (`String` in metal,
///   `HxString` in portable), so the profile bridge currently happens at the generated Haxe layer.
///
/// What
/// - Shared compact/pretty stringify core used by the public `hxrt::json` entry points.
///
/// How
/// - Serializes directly from runtime `Dynamic` shapes into JSON bytes.
/// - Returns owned Rust `String` so the higher-level Haxe bridge can preserve the active profile
///   string contract without duplicating the serializer path here.
fn stringify_with_space(value: Dynamic, space: Option<&str>) -> String {
    if let Some(indent) = space {
        use serde_json::ser::{PrettyFormatter, Serializer};

        let mut buf: Vec<u8> = vec![];
        let formatter = PrettyFormatter::with_indent(indent.as_bytes());
        let mut ser = Serializer::with_formatter(&mut buf, formatter);
        DynamicJson(&value)
            .serialize(&mut ser)
            .unwrap_or_else(|e| throw_json(e.to_string()));
        return String::from_utf8(buf).unwrap_or_else(|e| throw_json(e.to_string()));
    }

    serde_json::to_string(&DynamicJson(&value)).unwrap_or_else(|e| throw_json(e.to_string()))
}

/// Encode a Haxe `Dynamic` value as compact JSON.
pub fn stringify(value: Dynamic) -> String {
    stringify_with_space(value, None)
}

/// Encode a Haxe `Dynamic` value as pretty-printed JSON using the provided indent string.
pub fn stringify_pretty<S: AsRef<str>>(value: Dynamic, space: S) -> String {
    stringify_with_space(value, Some(space.as_ref()))
}

/// Encode a Haxe `Dynamic` value as JSON after applying a Haxe-style replacer callback.
///
/// Semantics:
/// - The replacer is called first with the root key `""`.
/// - Object members use their field name as the key.
/// - Array items use their decimal string index (`"0"`, `"1"`, ...).
/// - The replacer runs before descending into the returned value's children, matching
///   upstream `haxe.format.JsonPrinter`.
pub fn stringify_with_replacer(
    value: Dynamic,
    replacer: HxDynRef<dyn Fn(Dynamic, Dynamic) -> Dynamic + Send + Sync>,
) -> String {
    let normalized = json_value_to_dynamic(dynamic_to_json_value(&value));
    let replaced = apply_json_replacer("", normalized, &*replacer);
    stringify(replaced)
}

/// Encode a Haxe `Dynamic` value as pretty-printed JSON after applying a Haxe-style replacer callback.
pub fn stringify_with_replacer_pretty<S: AsRef<str>>(
    value: Dynamic,
    replacer: HxDynRef<dyn Fn(Dynamic, Dynamic) -> Dynamic + Send + Sync>,
    space: S,
) -> String {
    let normalized = json_value_to_dynamic(dynamic_to_json_value(&value));
    let replaced = apply_json_replacer("", normalized, &*replacer);
    stringify_pretty(replaced, space)
}

/// Return a stable runtime kind tag for JSON-backed dynamic values.
///
/// Kind values:
/// - `0`: null
/// - `1`: bool
/// - `2`: int
/// - `3`: float
/// - `4`: string
/// - `5`: array
/// - `6`: object
pub fn value_kind(value: &Dynamic) -> i32 {
    if value.is_null() {
        return VALUE_KIND_NULL;
    }
    if value.downcast_ref::<bool>().is_some() {
        return VALUE_KIND_BOOL;
    }
    if let Some(kind) = dynamic_json_number_kind(value) {
        return kind;
    }
    if dynamic_json_str(value).is_some() {
        return VALUE_KIND_STRING;
    }
    if value.downcast_ref::<Array<Dynamic>>().is_some() {
        return VALUE_KIND_ARRAY;
    }
    if value.downcast_ref::<HxRef<DynObject>>().is_some() {
        return VALUE_KIND_OBJECT;
    }

    throw_json(format!(
        "Unsupported value in haxe.Json.parseValue boundary: {}",
        value.to_haxe_string()
    ))
}

pub fn value_as_bool(value: &Dynamic) -> bool {
    value
        .downcast_ref::<bool>()
        .copied()
        .unwrap_or_else(|| throw_json(String::from("Expected JSON bool")))
}

pub fn value_as_int(value: &Dynamic) -> i32 {
    value
        .downcast_ref::<i32>()
        .copied()
        .unwrap_or_else(|| throw_json(String::from("Expected JSON int")))
}

pub fn value_as_float(value: &Dynamic) -> f64 {
    value
        .downcast_ref::<f64>()
        .copied()
        .unwrap_or_else(|| throw_json(String::from("Expected JSON float")))
}

pub fn value_as_string(value: &Dynamic) -> String {
    dynamic_json_owned_string(value)
        .unwrap_or_else(|| throw_json(String::from("Expected JSON string")))
}

pub fn value_array_length(value: &Dynamic) -> i32 {
    value
        .downcast_ref::<Array<Dynamic>>()
        .map(|a| a.len() as i32)
        .unwrap_or_else(|| throw_json(String::from("Expected JSON array")))
}

pub fn value_array_get(value: &Dynamic, index: i32) -> Dynamic {
    let Some(arr) = value.downcast_ref::<Array<Dynamic>>() else {
        throw_json(String::from("Expected JSON array"));
    };
    let idx = index.max(0) as usize;
    arr.get(idx)
        .unwrap_or_else(|| throw_json(format!("JSON array index out of range: {index}")))
}

pub fn value_object_keys<S>(value: &Dynamic) -> Array<S>
where
    S: From<String> + Clone,
{
    let Some(obj) = value.downcast_ref::<HxRef<DynObject>>() else {
        throw_json(String::from("Expected JSON object"));
    };
    crate::dynamic::dyn_object_keys::<S>(obj)
}

pub fn value_object_field<K>(value: &Dynamic, key: K) -> Dynamic
where
    K: AsRef<str>,
{
    let Some(obj) = value.downcast_ref::<HxRef<DynObject>>() else {
        throw_json(String::from("Expected JSON object"));
    };
    crate::dynamic::dyn_object_get(obj, key.as_ref())
}

#[cfg(test)]
mod tests {
    use super::{parse, stringify};
    use crate::anon::Anon;
    use crate::array::Array;
    use crate::cell::HxRef;
    use crate::dynamic::Dynamic;
    use crate::string::HxString;

    #[test]
    fn stringify_serializes_anon_payloads_directly() {
        let flags = Array::<Dynamic>::new();
        flags.push(Dynamic::from(true));
        flags.push(Dynamic::from(false));

        let nested = HxRef::new(Anon::new());
        crate::anon::anon_set(&nested, "count", Dynamic::from(3));

        let payload = HxRef::new(Anon::new());
        crate::anon::anon_set(&payload, "flags", Dynamic::from(flags));
        crate::anon::anon_set(&payload, "id", Dynamic::from(7));
        crate::anon::anon_set(
            &payload,
            "label",
            Dynamic::from(HxString::from(String::from("json-7"))),
        );
        crate::anon::anon_set(&payload, "nested", Dynamic::from(nested));

        let json = stringify(Dynamic::from(payload));
        assert_eq!(
            json,
            r#"{"flags":[true,false],"id":7,"label":"json-7","nested":{"count":3}}"#
        );
    }

    #[test]
    fn stringify_round_trips_parsed_dyn_objects() {
        let json = r#"{"flags":[true,false],"id":7,"label":"json-7","nested":{"count":3}}"#;
        let parsed = parse(json);
        assert_eq!(stringify(parsed), json);
    }
}
