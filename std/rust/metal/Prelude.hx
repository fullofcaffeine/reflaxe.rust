package rust.metal;

/**
 * Canonical import hub for Rust-first metal code.
 *
 * Why
 * - Metal code frequently uses the same borrow/ownership-oriented surfaces (`Ref`, `MutRef`,
 *   `Slice`, `Option`, `Result`, etc.).
 * - A shared module keeps those choices explicit and documents the intended “metal style”.
 *
 * What
 * - Type aliases to core `rust.*` ownership/borrow/value surfaces.
 * - A no-op anchor class (`Prelude`) so projects can depend on a stable module path.
 *
 * How
 * - Use explicit imports from this module in metal-focused code, for example:
 *   `import rust.metal.Prelude.Ref;`
 *   `import rust.metal.Prelude.Option;`
 */
typedef Ref<T> = rust.Ref<T>;

typedef MutRef<T> = rust.MutRef<T>;
typedef Slice<T> = rust.Slice<T>;
typedef MutSlice<T> = rust.MutSlice<T>;
typedef Str = rust.Str;
typedef Option<T> = rust.Option<T>;
typedef Result<T, E> = rust.Result<T, E>;
typedef Vec<T> = rust.Vec<T>;
typedef HashMap<K, V> = rust.HashMap<K, V>;

class Prelude {
	public static function use():Void {}
}
