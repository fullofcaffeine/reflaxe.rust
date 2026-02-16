package haxe.ds;

import haxe.Constraints.IMap;

/**
	EnumValueMap (Rust target)

	Why
	- `Map<EnumValue, V>` specializes to `haxe.ds.EnumValueMap` in the standard library.
	- Rust requires keys that implement hashing + equality, but Haxe enum values are structurally compared.

	What
	- A pragmatic `EnumValueMap<K, V>` implementation for the Rust target.
	- Uses a stable-ish string key derived from `Std.string(key)` to index into two internal maps.

	How
	- We compute `id = Std.string(key)` and store:
	  - `keysMap`: id -> original key (so `keys()` yields `K`)
	  - `valuesMap`: id -> value
	- This requires `K: Clone` in Rust output for iteration/copy, which is typically satisfied because reflaxe.rust
	  derives `Clone` for emitted enums by default.
**/
@:rustGeneric([
	"K: Clone + Send + Sync + 'static + std::fmt::Debug",
	"V: Clone + Send + Sync + 'static + std::fmt::Debug"
])
class EnumValueMap<K:EnumValue, V> implements IMap<K, V> {
	var keysMap:rust.HashMap<String, K>;
	var valuesMap:rust.HashMap<String, V>;

	public function new():Void {
		keysMap = new rust.HashMap();
		valuesMap = new rust.HashMap();
	}

	public function set(key:K, value:V):Void {
		var id = Std.string(key);
		#if macro
		#else
		untyped __rust__("{ let mut __s = {0}.borrow_mut(); __s.keys_map.insert({1}.clone(), {2}); __s.values_map.insert({1}, {3}); }", this, id, key, value);
		#end
	}

	@:rustReturn("Option<V>")
	public function get(key:K):Null<V> {
		var id = Std.string(key);
		#if macro
		return null;
		#else
		return untyped __rust__("{0}.borrow().values_map.get(&{1}).cloned()", this, id);
		#end
	}

	public function exists(key:K):Bool {
		var id = Std.string(key);
		#if macro
		return false;
		#else
		return untyped __rust__("{0}.borrow().values_map.contains_key(&{1})", this, id);
		#end
	}

	public function remove(key:K):Bool {
		var id = Std.string(key);
		#if macro
		return false;
		#else
		return
			untyped __rust__("{ let mut __s = {0}.borrow_mut(); let __existed = __s.values_map.remove(&{1}).is_some(); __s.keys_map.remove(&{1}); __existed }",
				this, id);
		#end
	}

	public function keys():Iterator<K> {
		#if macro
		return [].iterator();
		#else
		return untyped __rust__("hxrt::iter::Iter::from_vec({0}.borrow().keys_map.values().cloned().collect::<Vec<_>>())", this);
		#end
	}

	public function iterator():Iterator<V> {
		#if macro
		return [].iterator();
		#else
		return untyped __rust__("hxrt::iter::Iter::from_vec({0}.borrow().values_map.values().cloned().collect::<Vec<_>>())", this);
		#end
	}

	public function keyValueIterator():KeyValueIterator<K, V> {
		#if macro
		return [].iterator();
		#else
		return
			untyped __rust__("hxrt::iter::Iter::from_vec({ let __s = {0}.borrow(); __s.values_map.iter().map(|(id, v)| hxrt::iter::KeyValue { key: __s.keys_map.get(id).unwrap().clone(), value: v.clone() }).collect::<Vec<_>>() })",
			this);
		#end
	}

	public function copy():EnumValueMap<K, V> {
		var out = new EnumValueMap<K, V>();
		#if macro
		#else
		untyped __rust__("{ let __s = {1}.borrow(); let mut __o = {0}.borrow_mut(); __o.keys_map = __s.keys_map.clone(); __o.values_map = __s.values_map.clone(); }",
			out,
			this);
		#end
		return out;
	}

	public function toString():String {
		#if macro
		return "{}";
		#else
		return untyped __rust__("format!(\"{:?}\", {0}.borrow().values_map)", this);
		#end
	}

	public function clear():Void {
		#if macro
		#else
		untyped __rust__("{ let mut __s = {0}.borrow_mut(); __s.keys_map.clear(); __s.values_map.clear(); }", this);
		#end
	}
}
