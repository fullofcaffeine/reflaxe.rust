use std::any::Any;

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
pub struct Dynamic(Option<Box<dyn AnyClone>>, &'static str);

impl Clone for Dynamic {
    #[inline]
    fn clone(&self) -> Self {
        Dynamic(self.0.clone(), self.1)
    }
}

impl Dynamic {
    #[inline]
    pub fn null() -> Dynamic {
        Dynamic(None, "null")
    }

    #[inline]
    pub fn from<T>(value: T) -> Dynamic
    where
        T: Any + Clone + Send + Sync + 'static,
    {
        Dynamic(Some(Box::new(value)), std::any::type_name::<T>())
    }

    pub fn to_haxe_string(&self) -> String {
        if self.0.is_none() {
            return String::from("null");
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
                    Err(Dynamic(Some(b), self.1))
                }
            }
        }
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

#[cfg(test)]
mod tests {
    use super::Dynamic;

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
}
