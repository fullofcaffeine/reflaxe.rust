package rust;

/**
 * rust.Slice<T>
 *
 * Represents a borrowed slice (`&[T]`) in Rust output.
 *
 * IMPORTANT:
 * - Like `Ref<T>`, this is a borrowed view; avoid storing long-lived slices.
 * - Prefer constructing via `SliceTools.fromVec` or borrow-scoped helpers.
 */
@:coreType
extern abstract Slice<T> {
	/**
	 * `iterator()` exists to make `for (x in slice)` typecheck in Haxe.
	 *
	 * The compiler special-cases `iterator()` on `rust.Slice<T>` and lowers it to
	 * `slice.iter().cloned()` in Rust output.
	 */
	@:native("iter")
	public function iterator(): Iterator<T>;
}
