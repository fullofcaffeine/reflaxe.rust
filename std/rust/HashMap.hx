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
}

