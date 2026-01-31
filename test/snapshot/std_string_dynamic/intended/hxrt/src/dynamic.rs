use std::any::Any;

pub trait AnyClone: Any {
    fn clone_box(&self) -> Box<dyn AnyClone>;
    fn as_any(&self) -> &dyn Any;
}

impl<T> AnyClone for T
where
    T: Any + Clone + 'static,
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
        self.clone_box()
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
pub struct Dynamic(Box<dyn AnyClone>, &'static str);

impl Clone for Dynamic {
    #[inline]
    fn clone(&self) -> Self {
        Dynamic(self.0.clone(), self.1)
    }
}

impl Dynamic {
    #[inline]
    pub fn from<T>(value: T) -> Dynamic
    where
        T: Any + Clone + 'static,
    {
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
    pub fn downcast_ref<T: Any + 'static>(&self) -> Option<&T> {
        let any = self.0.as_ref().as_any();
        any.downcast_ref::<T>()
    }

    #[inline]
    pub fn downcast<T: Any + 'static>(self) -> Result<Box<T>, Dynamic> {
        if !self.0.as_ref().as_any().is::<T>() {
            return Err(self);
        }

        // At this point the type matches; this downcast must succeed.
        let any: Box<dyn Any> = self.0;
        Ok(any.downcast::<T>().ok().unwrap())
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
    T: Any + Clone + 'static,
{
    Dynamic::from(value)
}

#[cfg(test)]
mod tests {
    use super::Dynamic;

    #[test]
    fn downcast_and_to_haxe_string_work() {
        let d = Dynamic::from(String::from("hi"));
        let any = d.0.as_any();
        assert!(any.is::<String>(), "expected Any to be String");
        assert_eq!(any.downcast_ref::<String>().unwrap().as_str(), "hi");
        assert_eq!(
            d.0.as_any().downcast_ref::<String>().unwrap().as_str(),
            "hi"
        );
        assert_eq!(d.downcast_ref::<String>().unwrap().as_str(), "hi");
        assert_eq!(d.to_haxe_string(), "hi");

        let d2 = Dynamic::from(123i32);
        assert_eq!(d2.to_haxe_string(), "123");
    }
}
