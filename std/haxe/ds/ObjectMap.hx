package haxe.ds;

import haxe.Constraints.IMap;

/**
	ObjectMap (Rust target)

	Why
	- Haxe `ObjectMap<K, V>` is used when `K` is an object/structure key (behind `Map<K, V>` specialization).
	- Rust requires a hashable key; for portable Haxe object keys we need an identity-based strategy.

	What
	- A best-effort `ObjectMap<K, V>` implementation for the Rust target.
	- Intended for **class instance** keys (`K` being a portable Haxe class), which are represented as
	  `Rc<RefCell<...>>` in Rust output and can be identity-keyed.

	How
	- We compute an identity string from the key's underlying `Rc` pointer (`format!("{:p}", Rc::as_ptr(...))`).
	- Two internal hash maps are kept:
	  - `keysMap`: id -> original key (so `keys()` can yield `K`)
	  - `valuesMap`: id -> value
	- Limitations (documented):
	  - Keys that are not portable Haxe class instances may not compile/work (because the identity function relies on `Rc`).
	  - Value-returning operations clone (`K: Clone`, `V: Clone`) for Haxe-like reuse semantics.
**/
@:rustGeneric([
	"K: hxrt::hxref::HxRefLike + Clone + Send + Sync + 'static + std::fmt::Debug",
	"V: Clone + Send + Sync + 'static + std::fmt::Debug"
])
class ObjectMap<K:{}, V> implements IMap<K, V> {
	var keysMap: rust.HashMap<String, K>;
	var valuesMap: rust.HashMap<String, V>;

	public function new():Void {
		keysMap = new rust.HashMap();
		valuesMap = new rust.HashMap();
	}

	inline function keyId(key:K):String {
		#if macro
		return "";
		#else
		return untyped __rust__("hxrt::hxref::ptr_id(&{0})", key);
		#end
	}

	public function set(key:K, value:V):Void {
		var id = keyId(key);
		#if macro
		#else
		untyped __rust__(
			"{ let mut __s = {0}.borrow_mut(); __s.keys_map.insert({1}.clone(), {2}); __s.values_map.insert({1}, {3}); }",
			this,
			id,
			key,
			value
		);
		#end
	}

	@:rustReturn("Option<V>")
	public function get(key:K):Null<V> {
		var id = keyId(key);
		#if macro
		return null;
		#else
		return untyped __rust__("{0}.borrow().values_map.get(&{1}).cloned()", this, id);
		#end
	}

	public function exists(key:K):Bool {
		var id = keyId(key);
		#if macro
		return false;
		#else
		return untyped __rust__("{0}.borrow().values_map.contains_key(&{1})", this, id);
		#end
	}

	public function remove(key:K):Bool {
		var id = keyId(key);
		#if macro
		return false;
		#else
		return untyped __rust__(
			"{ let mut __s = {0}.borrow_mut(); let __existed = __s.values_map.remove(&{1}).is_some(); __s.keys_map.remove(&{1}); __existed }",
			this,
			id
		);
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
		return untyped __rust__(
			"hxrt::iter::Iter::from_vec({ let __s = {0}.borrow(); __s.values_map.iter().map(|(id, v)| hxrt::iter::KeyValue { key: __s.keys_map.get(id).unwrap().clone(), value: v.clone() }).collect::<Vec<_>>() })",
			this
		);
		#end
	}

	public function copy():ObjectMap<K, V> {
		var out = new ObjectMap<K, V>();
		#if macro
		#else
		untyped __rust__(
			"{ let __s = {1}.borrow(); let mut __o = {0}.borrow_mut(); __o.keys_map = __s.keys_map.clone(); __o.values_map = __s.values_map.clone(); }",
			out,
			this
		);
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
