package rust;

/**
 * ArrayBorrow
 *
 * Borrow helpers for Haxe `Array<T>` that map to the underlying Rust storage.
 *
 * Why:
 * - On this target, Haxe `Array<T>` maps to `hxrt::array::Array<T>` (a shared `HxRef<Vec<T>>`
 *   backed by `Arc` + interior mutability locks in `hxrt::cell`).
 * - Rust APIs often want slices (`&[T]` / `&mut [T]`) instead of a higher-level container type.
 * - We want **zero-clone** slice access without using `__rust__` directly in app code.
 *
 * What:
 * - `withSlice`: temporarily borrows an `Array<T>` as `rust.Slice<T>` (`&[T]`) inside a callback.
 * - `withMutSlice`: temporarily borrows an `Array<T>` as `rust.MutSlice<T>` (`&mut [T]`) inside a callback.
 *
 * How:
 * - `ArrayBorrowNative` is a typed extern bound to `std/rust/native/array_borrow_tools.rs`.
 * - That native module delegates to runtime helpers (`hxrt::array::with_slice`,
 *   `hxrt::array::with_mut_slice`) and keeps the borrow guard scoped to the callback.
 * - Callers stay in typed Haxe code without raw `__rust__` expressions.
 *
 * Rust closure note (important):
 * - For `Array<T>`, these helpers must pass a real Rust closure into the runtime.
 * - That closure currently typechecks as `Fn(...)`, which means it cannot mutate captured outer
 *   locals in Rust output.
 * - Prefer returning a value from the callback instead of assigning to captured variables:
 *   - Good: `var n = ArrayBorrow.withSlice(a, s -> SliceTools.len(s));`
 *   - Avoid: `var n = 0; ArrayBorrow.withSlice(a, s -> { n = ...; });`
 *
 * Rules / gotchas:
 * - Never return/store the `Slice`/`MutSlice` outside the callback; Haxe cannot express Rust lifetimes.
 * - Avoid nested mutable borrows on the same array while a mutable slice is live; the runtime lock
 *   can block/reject conflicting access depending on call ordering.
 */
class ArrayBorrow {
	public static function withSlice<T, R>(array:Array<T>, f:Slice<T>->R):R {
		return ArrayBorrowNative.withSlice(array, f);
	}

	public static function withMutSlice<T, R>(array:Array<T>, f:MutSlice<T>->R):R {
		return ArrayBorrowNative.withMutSlice(array, f);
	}
}

/**
 * Typed native boundary for `rust.ArrayBorrow`.
 *
 * Why
 * - Slice callback plumbing depends on Rust-specific callback aliases
 *   (`hxrt::array::SliceCallback` / `MutSliceCallback`).
 * - Centralizing that bridge in a native helper avoids raw fallback in first-party Haxe code.
 *
 * How
 * - Bound to crate-local `array_borrow_tools.rs` through `@:native` + `@:rustExtraSrc`.
 */
@:native("crate::array_borrow_tools::ArrayBorrowTools")
@:rustExtraSrc("rust/native/array_borrow_tools.rs")
extern class ArrayBorrowNative {
	public static function withSlice<T, R>(array:Ref<Array<T>>, f:Slice<T>->R):R;
	public static function withMutSlice<T, R>(array:Ref<Array<T>>, f:MutSlice<T>->R):R;
}
