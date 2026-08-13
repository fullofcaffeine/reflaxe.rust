pub struct UnsafeProbe;

impl UnsafeProbe {
    pub fn read_known_value() -> i32 {
        let value = 7_i32;
        // This operation represents a small audited native island. The pointer
        // is valid for this read, but Rust still requires an unsafe block.
        unsafe { std::ptr::read_volatile(&value) }
    }
}
