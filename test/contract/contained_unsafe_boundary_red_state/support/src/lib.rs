#![deny(warnings)]

pub struct UnsafeProbe;

impl UnsafeProbe {
    pub fn read_known_value() -> i32 {
        let value = 7_i32;
        // The support crate contains the native operation and exposes a safe
        // method. Its unsafe policy is separate from the application crate.
        unsafe { std::ptr::read_volatile(&value) }
    }
}
