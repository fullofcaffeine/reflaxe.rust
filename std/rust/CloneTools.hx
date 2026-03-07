package rust;

import rust.Ref;

/**
 * `rust.CloneTools`
 *
 * Why
 * - Some portable std overrides need to duplicate a generic owned Rust value while staying on a
 *   typed Haxe surface.
 * - Repeating inline raw `__rust__("{0}.clone()")` at each callsite would hide the boundary and
 *   make metal-fallback auditing noisier.
 *
 * What
 * - A tiny typed helper bound to a hand-written Rust module that performs `Clone::clone`.
 *
 * How
 * - `@:native("crate::clone_tools::CloneTools")` binds to `std/rust/native/clone_tools.rs`.
 * - Callers stay typed in Haxe and only cross the backend-specific boundary through this audited
 *   extern surface.
 */
@:native("crate::clone_tools::CloneTools")
@:rustExtraSrc("rust/native/clone_tools.rs")
extern class CloneTools {
	@:rustGeneric("T: Clone")
	public static function cloneValue<T>(value:Ref<T>):T;
}
