package rust;

import rust.Ref;

/**
 * `rust.RefTools`
 *
 * Why
 * - Borrow-scoped code sometimes needs to derive an owned `Clone` value while staying on a
 *   typed Haxe surface.
 * - Repeating inline raw `__rust__("{0}.clone()")` at each callsite would hide the boundary and
 *   make metal-fallback auditing noisier.
 *
 * What
 * - A narrow typed borrow facade bound to a hand-written Rust module that performs `Clone::clone`.
 *
 * How
 * - `@:native("crate::clone_tools::CloneTools")` binds to `std/rust/native/clone_tools.rs`.
 * - Callers stay typed in Haxe and cross the backend-specific clone boundary through this audited
 *   extern surface.
 */
@:native("crate::clone_tools::CloneTools")
@:rustExtraSrc("rust/native/clone_tools.rs")
extern class RefTools {
	/**
	 * Produces an owned clone from a lexically borrowed value.
	 *
	 * Why: Returning the borrow would violate the scoped-region contract, while many Rust values can
	 * safely leave the callback by cloning.
	 * What: Calls `Clone::clone` and returns the owned `T`.
	 * How: The Rust `T: Clone` bound is emitted from `@:rustGeneric`. `@:native("cloneValue")`
	 * preserves the narrow helper's existing Rust symbol while the Haxe API uses the semantic
	 * `toOwned` name; clone cost remains explicit and belongs to the caller's chosen type.
	 */
	@:rustGeneric("T: Clone")
	@:native("cloneValue")
	public static function toOwned<T>(value:Ref<T>):T;
}
