use std::any::Any;

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
pub struct Dynamic(Box<dyn Any>, &'static str);

impl Dynamic {
    #[inline]
    pub fn from<T: Any + 'static>(value: T) -> Dynamic {
        Dynamic(Box::new(value), std::any::type_name::<T>())
    }

    pub fn to_haxe_string(&self) -> String {
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
    pub fn downcast<T: Any + 'static>(self) -> Result<Box<T>, Dynamic> {
        match self.0.downcast::<T>() {
            Ok(v) => Ok(v),
            Err(v) => Err(Dynamic(v, self.1)),
        }
    }

    #[inline]
    pub fn downcast_ref<T: Any + 'static>(&self) -> Option<&T> {
        self.0.downcast_ref::<T>()
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
pub fn from<T: Any + 'static>(value: T) -> Dynamic {
    Dynamic::from(value)
}
