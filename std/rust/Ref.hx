package rust;

/**
 * rust.Ref<T>
 *
 * Why:
 * - Many idiomatic Rust APIs accept `&T` to read data without moving/allocating.
 * - Haxe does not have lifetime syntax, so we model borrows as **compile-time-only types**
 *   that the backend recognizes and prints as Rust borrows.
 *
 * What:
 * - `Ref<T>` represents an immutable borrowed reference (`&T`) in emitted Rust.
 * - This is **not** a runtime wrapper type; it exists only to guide typing + codegen.
 *
 * How:
 * - `@:coreType` marks this as a “core/platform” type so Haxe does not expect a normal
 *   Haxe implementation / runtime representation.
 * - `@:from` lets Haxe typecheck calls where a `T` is passed to a parameter that expects
 *   `Ref<T>`; in typed AST this usually becomes a `cast`, and the compiler emits `&`.
 *
 * Notes:
 * - Prefer borrow-scoped helpers like `rust.Borrow.withRef(value, ref -> { ... })`
 *   instead of storing `Ref<T>` long-term (Haxe cannot express Rust lifetimes).
 *
 * Related:
 * - `rust.MutRef<T>` for mutable borrows (`&mut T`).
 */
@:coreType
extern abstract Ref<T> {
	@:from public static inline function fromValue<T>(v: T): Ref<T> {
		return cast v;
	}
}
