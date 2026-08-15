#![forbid(unsafe_code)]

mod platform;

pub struct Api;

impl Api {
    pub fn answer() -> i32 {
        if platform::supported() { 42 } else { 0 }
    }
}
