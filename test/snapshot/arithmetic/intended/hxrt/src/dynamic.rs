use std::any::Any;

/// Haxe-style dynamic value.
///
/// This is intentionally minimal for now:
/// - payload is a boxed `Any` so we can downcast at runtime
/// - implements `Debug` so `trace(dynamic)` / `Std.string(dynamic)` can work for common primitives
pub struct Dynamic(Box<dyn Any>);

impl Dynamic {
    #[inline]
    pub fn from<T: Any + 'static>(value: T) -> Dynamic {
        Dynamic(Box::new(value))
    }

    #[inline]
    pub fn downcast<T: Any + 'static>(self) -> Result<Box<T>, Dynamic> {
        match self.0.downcast::<T>() {
            Ok(v) => Ok(v),
            Err(v) => Err(Dynamic(v)),
        }
    }

    #[inline]
    pub fn downcast_ref<T: Any + 'static>(&self) -> Option<&T> {
        self.0.downcast_ref::<T>()
    }
}

impl std::fmt::Debug for Dynamic {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        if let Some(v) = self.downcast_ref::<String>() {
            return write!(f, "{}", v);
        }
        if let Some(v) = self.downcast_ref::<i32>() {
            return write!(f, "{}", v);
        }
        if let Some(v) = self.downcast_ref::<f64>() {
            return write!(f, "{}", v);
        }
        if let Some(v) = self.downcast_ref::<bool>() {
            return write!(f, "{}", v);
        }

        write!(f, "<Dynamic>")
    }
}

#[inline]
pub fn from<T: Any + 'static>(value: T) -> Dynamic {
    Dynamic::from(value)
}
