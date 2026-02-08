package rust;

/**
 * ArrayBorrow
 *
 * Borrow helpers for Haxe `Array<T>` that map to the underlying Rust storage.
 *
 * Why:
 * - On this target, Haxe `Array<T>` maps to `hxrt::array::Array<T>` (a shared `Rc<RefCell<Vec<T>>>`).
 * - Rust APIs often want slices (`&[T]` / `&mut [T]`) instead of a higher-level container type.
 * - We want **zero-clone** slice access without using `__rust__` directly in app code.
 *
 * What:
 * - `withSlice`: temporarily borrows an `Array<T>` as `rust.Slice<T>` (`&[T]`) inside a callback.
 * - `withMutSlice`: temporarily borrows an `Array<T>` as `rust.MutSlice<T>` (`&mut [T]`) inside a callback.
 *
 * How:
 * - These functions call into the runtime crate (`hxrt::array::with_slice` / `with_mut_slice`).
 * - The runtime creates a `RefCell` borrow guard and passes the slice to the callback.
 * - The borrow guard is dropped when the call returns, so the slice cannot escape.
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
 * - Avoid re-borrowing the same array mutably while a slice is live (Rust will panic on nested `RefCell` borrows).
 */
class ArrayBorrow {
	public static function withSlice<T, R>(array: Array<T>, f: Slice<T>->R): R {
		return untyped __rust__("hxrt::array::with_slice({0}, {1})", array, f);
	}

	public static function withMutSlice<T, R>(array: Array<T>, f: MutSlice<T>->R): R {
		return untyped __rust__("hxrt::array::with_mut_slice({0}, {1})", array, f);
	}
}
