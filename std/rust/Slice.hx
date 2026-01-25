package rust;

/**
 * rust.Slice<T>
 *
 * Represents a borrowed slice (`&[T]`) in Rust output.
 *
 * IMPORTANT:
 * - Like `Ref<T>`, this is a borrowed view; avoid storing long-lived slices.
 * - Prefer constructing via `SliceTools.fromVec` or `SliceTools.with(...)` (borrow-scoped).
 */
@:coreType
extern abstract Slice<T> {
	/**
	 * Allow passing a borrowed `&Vec<T>` anywhere a `rust.Slice<T>` is expected.
	 *
	 * Rust has an implicit coercion from `&Vec<T>` to `&[T]`, so codegen treats this as a no-op.
	 */
	@:from public static inline function fromRefVec<T>(r: Ref<Vec<T>>): Slice<T> {
		return cast r;
	}

	/**
	 * Allow passing a borrowed `&Array<T>` (portable `Vec<T>`) anywhere a `rust.Slice<T>` is expected.
	 */
	@:from public static inline function fromRefArray<T>(r: Ref<Array<T>>): Slice<T> {
		return cast r;
	}

	/**
	 * `iterator()` exists to make `for (x in slice)` typecheck in Haxe.
	 *
	 * The compiler special-cases `iterator()` on `rust.Slice<T>` and lowers it to
	 * `slice.iter().cloned()` in Rust output.
	 */
	@:native("iter")
	public function iterator(): Iterator<T>;
}
