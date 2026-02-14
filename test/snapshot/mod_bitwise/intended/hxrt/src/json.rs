use crate::array::Array;
use crate::cell::HxRef;
use crate::dynamic::{DynObject, Dynamic};
use crate::exception;
use crate::string::HxString;
use serde_json::Value;

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

fn dynamic_json_string(v: &Dynamic) -> Option<String> {
    if let Some(s) = v.downcast_ref::<String>() {
        return Some(s.clone());
    }
    if let Some(s) = v.downcast_ref::<HxString>() {
        return Some(s.as_deref().unwrap_or("").to_string());
    }
    None
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

/// Parse a JSON string into Haxe `Dynamic` values.
///
/// Semantics (target baseline):
/// - JSON objects => `HxRef<hxrt::dynamic::DynObject>` boxed into `Dynamic`
/// - JSON arrays => `hxrt::array::Array<Dynamic>` boxed into `Dynamic`
/// - numbers => `i32` when integral and in range, otherwise `f64`
/// - invalid JSON => throws a catchable Haxe exception payload (`String`)
pub fn parse(text: &str) -> Dynamic {
    match serde_json::from_str::<Value>(text) {
        Ok(v) => json_value_to_dynamic(v),
        Err(e) => throw_json(format!("Invalid JSON: {e}")),
    }
}

/// Encode a Haxe `Dynamic` value as JSON.
///
/// `space` enables pretty printing (indent string per nesting level).
pub fn stringify(value: &Dynamic, space: Option<&str>) -> String {
    let v = dynamic_to_json_value(value);

    if let Some(indent) = space {
        use serde::Serialize;
        use serde_json::ser::{PrettyFormatter, Serializer};
        use serde_json::value::Value as SerValue;

        let mut buf: Vec<u8> = vec![];
        let formatter = PrettyFormatter::with_indent(indent.as_bytes());
        let mut ser = Serializer::with_formatter(&mut buf, formatter);
        SerValue::serialize(&v, &mut ser).unwrap_or_else(|e| throw_json(e.to_string()));
        return String::from_utf8(buf).unwrap_or_else(|e| throw_json(e.to_string()));
    }

    serde_json::to_string(&v).unwrap_or_else(|e| throw_json(e.to_string()))
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
pub fn value_kind(value: Dynamic) -> i32 {
    let value = &value;
    if value.is_null() {
        return VALUE_KIND_NULL;
    }
    if value.downcast_ref::<bool>().is_some() {
        return VALUE_KIND_BOOL;
    }
    if let Some(kind) = dynamic_json_number_kind(value) {
        return kind;
    }
    if dynamic_json_string(value).is_some() {
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

pub fn value_as_bool(value: Dynamic) -> bool {
    value
        .downcast_ref::<bool>()
        .copied()
        .unwrap_or_else(|| throw_json(String::from("Expected JSON bool")))
}

pub fn value_as_int(value: Dynamic) -> i32 {
    value
        .downcast_ref::<i32>()
        .copied()
        .unwrap_or_else(|| throw_json(String::from("Expected JSON int")))
}

pub fn value_as_float(value: Dynamic) -> f64 {
    value
        .downcast_ref::<f64>()
        .copied()
        .unwrap_or_else(|| throw_json(String::from("Expected JSON float")))
}

pub fn value_as_string(value: Dynamic) -> String {
    dynamic_json_string(&value).unwrap_or_else(|| throw_json(String::from("Expected JSON string")))
}

pub fn value_array_length(value: Dynamic) -> i32 {
    value
        .downcast_ref::<Array<Dynamic>>()
        .map(|a| a.len() as i32)
        .unwrap_or_else(|| throw_json(String::from("Expected JSON array")))
}

pub fn value_array_get(value: Dynamic, index: i32) -> Dynamic {
    let Some(arr) = value.downcast_ref::<Array<Dynamic>>() else {
        throw_json(String::from("Expected JSON array"));
    };
    let idx = index.max(0) as usize;
    arr.get(idx).unwrap_or_else(|| throw_json(format!("JSON array index out of range: {index}")))
}

pub fn value_object_keys<S>(value: Dynamic) -> Array<S>
where
    S: From<String> + Clone,
{
    let Some(obj) = value.downcast_ref::<HxRef<DynObject>>() else {
        throw_json(String::from("Expected JSON object"));
    };
    crate::dynamic::dyn_object_keys::<S>(obj)
}

pub fn value_object_field<K>(value: Dynamic, key: K) -> Dynamic
where
    K: AsRef<str>,
{
    let Some(obj) = value.downcast_ref::<HxRef<DynObject>>() else {
        throw_json(String::from("Expected JSON object"));
    };
    crate::dynamic::dyn_object_get(obj, key.as_ref())
}
