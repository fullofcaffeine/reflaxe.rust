package rust;

/**
 * rust.Str
 *
 * Why:
 * - Rust APIs heavily prefer `&str` for inputs (borrowed string slices) to avoid allocations.
 * - In the Rusty profile we want to express that intent directly from Haxe without moving/cloning.
 *
 * What:
 * - `Str` represents a borrowed string slice (`&str`) in emitted Rust.
 * - Like `rust.Ref<T>` / `rust.MutRef<T>`, this is a compile-time-only type: there is no Haxe runtime
 *   wrapper for it. It only exists to guide typing + codegen.
 *
 * How:
 * - `@:coreType` marks this as a “core/platform” type so Haxe does not expect a normal implementation
 *   or concrete runtime representation.
 * - `@:from` allows passing a borrowed `rust.Ref<String>` where a `rust.Str` is expected.
 * - Prefer borrow-scoped helpers (`rust.StrTools.with(...)`) so `Str` values do not escape.
 *
 * Notes:
 * - Avoid storing `Str` in locals/fields long-term; Haxe cannot express Rust lifetimes.
 * - Use `Str` mainly as a parameter/temporary value inside a borrow scope.
 */
@:coreType
extern abstract Str {
	@:from public static inline function fromRefString(r: Ref<String>): Str {
		return cast r;
	}
}
