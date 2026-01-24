package rust;

/**
 * rust.HashMap<K, V>
 *
 * Extern binding to Rust's `std::collections::HashMap<K, V>`.
 *
 * Notes:
 * - Rust's APIs typically accept borrowed keys (`&K`) for lookups; use `rust.Ref<K>` for those params.
 * - Methods that require `&mut self` are marked `@:rustMutating` so the idiomatic profile can infer `let mut`.
 */
@:native("std::collections::HashMap")
extern class HashMap<K, V> {
	public function new();

	@:rustMutating
	public function insert(key: K, value: V): Option<V>;

	public function get(key: Ref<K>): Option<Ref<V>>;

	@:native("contains_key")
	public function containsKey(key: Ref<K>): Bool;

	@:rustMutating
	public function remove(key: Ref<K>): Option<V>;

	/**
	 * Iterate borrowed keys (`&K`) without moving the map.
	 *
	 * Note: this returns a Rust iterator type, but is typed as a Haxe `Iterator`
	 * so `for (k in map.keys())` typechecks. The compiler lowers the for-loop to
	 * a Rust `for` directly.
	 */
	public function keys(): Iterator<Ref<K>>;

	/**
	 * Iterate borrowed values (`&V`) without moving the map.
	 */
	public function values(): Iterator<Ref<V>>;
}
