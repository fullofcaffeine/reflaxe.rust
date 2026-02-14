package reflaxe.rust;

/**
 * Compile-time output profile for the Rust backend.
 *
 * Why
 * - The backend intentionally supports multiple authoring modes, from Haxe-first portability
 *   to Rust-first APIs.
 * - Keeping profiles in a dedicated enum makes profile switches explicit and centrally typed.
 *
 * What
 * - `Portable`: default Haxe-first behavior.
 * - `Idiomatic`: same semantics as portable, cleaner Rust output.
 * - `Rusty`: Rust-first APIs with ownership/borrow-oriented surfaces.
 * - `Metal`: experimental Rust-first+ profile focused on typed Rust interop surfaces.
 *
 * How
 * - `ProfileResolver` maps defines to this enum (`reflaxe_rust_profile`, `rust_idiomatic`, `rust_metal`).
 * - Compiler/runtime feature gates should branch on this enum instead of re-parsing defines.
 */
enum RustProfile {
	Portable;
	Idiomatic;
	Rusty;
	Metal;
}
