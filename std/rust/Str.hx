package rust;

/**
 * rust.Str
 *
 * Represents a borrowed string slice (`&str`) in Rust output.
 *
 * IMPORTANT:
 * - This should generally be used as a parameter/temporary value, not stored.
 * - Construct via `Borrow.withRef(str, ...)` (as `Ref<String>`) and cast, or use `StrTools.with`.
 */
@:coreType
extern abstract Str {
	@:from public static inline function fromRefString(r: Ref<String>): Str {
		return cast r;
	}
}

