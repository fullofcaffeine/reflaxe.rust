package rust;

/**
 * rust.MutRef<T>
 *
 * Why:
 * - Rust APIs often take `&mut T` to mutate data without moving it.
 * - Haxe has no lifetime syntax, so we model borrows as **compile-time-only types**
 *   that the backend recognizes and prints as Rust borrows.
 *
 * What:
 * - `MutRef<T>` represents a mutable borrowed reference (`&mut T`) in emitted Rust.
 * - This is **not** a runtime wrapper type; it exists only to guide typing + codegen.
 *
 * How:
 * - `@:coreType` marks this as a “core/platform” type so Haxe does not expect a normal
 *   Haxe implementation / runtime representation.
 * - `@:from` lets Haxe typecheck calls where a `T` is passed to a parameter that expects
 *   `MutRef<T>`; in typed AST this usually becomes a `cast`, and the compiler emits `&mut`.
 *
 * Notes:
 * - Prefer borrow-scoped helpers like `rust.Borrow.withMut(value, mut -> { ... })`
 *   instead of storing `MutRef<T>` long-term (Haxe cannot express Rust lifetimes).
 */
@:coreType
extern abstract MutRef<T> {
	@:from public static inline function fromValue<T>(v: T): MutRef<T> {
		return cast v;
	}
}
