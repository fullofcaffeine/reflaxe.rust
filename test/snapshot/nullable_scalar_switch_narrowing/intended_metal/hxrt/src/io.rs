/// `hxrt::io`
///
/// Runtime representations for a small subset of `haxe.io.*` concepts.
///
/// Why
/// - Some stdlib APIs (notably `haxe.io.Bytes`) are expected to throw typed `haxe.io.Error` values
///   (for example `OutsideBounds`) that can be caught by type in `try/catch`.
/// - The Rust target's exception mechanism uses `hxrt::dynamic::Dynamic` payloads; typed catches are
///   implemented via `Dynamic::downcast::<T>()`. That means the thrown value must have a stable Rust
///   type that matches what the compiler uses for `haxe.io.Error`.
///
/// What
/// - `Error` is the Rust runtime representation of Haxe's `haxe.io.Error` enum.
///
/// How
/// - The compiler treats `haxe.io.Error` as a builtin enum and maps it to `hxrt::io::Error` in both
///   type emission and enum constructor paths.
/// - `Error::to_haxe_string()` provides stable stringification for `trace` / `Std.string`.
#[derive(Clone, Debug)]
pub enum Error {
    Blocked,
    OutsideBounds,
    Overflow,
    Custom(crate::dynamic::Dynamic),
}

impl Error {
    pub fn to_haxe_string(&self) -> String {
        match self {
            Error::Blocked => String::from("Blocked"),
            Error::OutsideBounds => String::from("OutsideBounds"),
            Error::Overflow => String::from("Overflow"),
            Error::Custom(e) => format!("Custom({})", e.to_haxe_string()),
        }
    }
}
