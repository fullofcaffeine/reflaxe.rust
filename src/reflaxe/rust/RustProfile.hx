package reflaxe.rust;

/**
 * Compile-time output profile for the Rust backend.
 *
 * Why
 * - The backend intentionally exposes two stable authoring contracts:
 *   Haxe-portable semantics (`Portable`) and Rust-first performance mode (`Metal`).
 * - Keeping profiles in a dedicated enum makes profile switches explicit and centrally typed.
 *
 * What
 * - `Portable`: default Haxe-first behavior.
 * - `Metal`: Rust-first profile focused on strict typed boundaries and performance-oriented output.
 *
 * How
 * - `ProfileResolver` maps `-D reflaxe_rust_profile=<portable|metal>` to this enum.
 * - Compiler/runtime feature gates should branch on this enum instead of re-parsing defines.
 */
enum RustProfile {
	Portable;
	Metal;
}
