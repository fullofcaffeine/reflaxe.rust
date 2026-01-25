package rust;

/**
 * rust.MutSlice<T>
 *
 * Why:
 * - Many Rust APIs accept `&mut [T]` to mutate a contiguous region without moving ownership.
 * - In the Rusty profile we want to express that intent directly from Haxe without forcing clones.
 *
 * What:
 * - `MutSlice<T>` represents a mutable borrowed slice (`&mut [T]`) in emitted Rust.
 * - Like `Ref<T>` / `MutRef<T>`, this is a compile-time-only type: it has no runtime representation
 *   in Haxe output.
 *
 * How:
 * - `@:coreType` tells the Haxe compiler this is a “platform/core” type.
 * - Codegen maps it directly to Rust `&mut [T]`.
 * - `@:from` conversions allow borrow-scoped helpers (`rust.Borrow.withMut(...)`) to pass a borrowed
 *   `MutRef<Vec<T>>` / `MutRef<Array<T>>` wherever a `MutSlice<T>` is expected.
 *
 * Notes:
 * - Prefer using `MutSlice<T>` as a parameter/temporary value, not storing it long-term.
 * - Haxe cannot express Rust lifetimes, so APIs should keep borrows short-lived (closure-scoped).
 */
@:coreType
extern abstract MutSlice<T> {
	@:from public static inline function fromMutRefVec<T>(r: MutRef<Vec<T>>): MutSlice<T> {
		return cast r;
	}

	@:from public static inline function fromMutRefArray<T>(r: MutRef<Array<T>>): MutSlice<T> {
		return cast r;
	}
}

