package rust;

/**
 * rust.MutRef<T>
 *
 * Represents a mutable borrowed reference (`&mut T`) in Rust output.
 */
@:coreType
extern abstract MutRef<T> {
	@:from public static inline function fromValue<T>(v: T): MutRef<T> {
		return cast v;
	}
}
