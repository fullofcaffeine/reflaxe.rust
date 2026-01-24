package rust;

/**
 * rust.Ref<T>
 *
 * Represents a borrowed reference (`&T`) in Rust output.
 *
 * Notes:
 * - This is intentionally minimal; most Rusty APIs should accept `Ref<T>` in signatures.
 * - Prefer using this in framework code and borrow-scoped helpers (`rust.Borrow`) rather than storing refs.
 */
@:coreType
extern abstract Ref<T> {
	@:from public static inline function fromValue<T>(v: T): Ref<T> {
		return cast v;
	}
}
