package haxe.ds;

import haxe.Constraints.IMap;

/**
	IntMap (Rust target)

	Why
	- `haxe.ds.IntMap` is a common specialization behind `Map<Int, V>`.
	- Rust's `HashMap<i32, V>` is a good backend representation for Haxe `Int` keys.

	What
	- Implements the standard Haxe `IntMap<T>` API on the Rust target.
	- Backed by Rust `std::collections::HashMap<i32, T>` under the portable class-instance model.

	How
	- `get()` returns `Null<T>` in Haxe; this is lowered to `Option<T>` in Rust output.
	- Value-returning operations clone (`T: Clone`).
	- Iterators are returned as owned Rust iterators (`Vec<_>.into_iter()`), intended for `for` loops.
**/
@:rustGeneric("T: Clone + Send + Sync + 'static + std::fmt::Debug")
class IntMap<T> implements IMap<Int, T> {
	var h:rust.HashMap<Int, T>;

	public function new():Void {
		h = new rust.HashMap();
	}

	public function set(key:Int, value:T):Void {
		#if macro
		#else
		untyped __rust__("{0}.borrow_mut().h.insert({1}, {2});", this, key, value);
		#end
	}

	@:rustReturn("Option<T>")
	public function get(key:Int):Null<T> {
		#if macro
		return null;
		#else
		return untyped __rust__("{0}.borrow().h.get(&{1}).cloned()", this, key);
		#end
	}

	public function exists(key:Int):Bool {
		#if macro
		return false;
		#else
		return untyped __rust__("{0}.borrow().h.contains_key(&{1})", this, key);
		#end
	}

	public function remove(key:Int):Bool {
		#if macro
		return false;
		#else
		return untyped __rust__("{0}.borrow_mut().h.remove(&{1}).is_some()", this, key);
		#end
	}

	public function keys():Iterator<Int> {
		#if macro
		return [].iterator();
		#else
		return untyped __rust__("hxrt::iter::Iter::from_vec({0}.borrow().h.keys().cloned().collect::<Vec<_>>())", this);
		#end
	}

	public function iterator():Iterator<T> {
		#if macro
		return [].iterator();
		#else
		return untyped __rust__("hxrt::iter::Iter::from_vec({0}.borrow().h.values().cloned().collect::<Vec<_>>())", this);
		#end
	}

	public function keyValueIterator():KeyValueIterator<Int, T> {
		#if macro
		return [].iterator();
		#else
		return
			untyped __rust__("hxrt::iter::Iter::from_vec({0}.borrow().h.iter().map(|(k, v)| hxrt::iter::KeyValue { key: k.clone(), value: v.clone() }).collect::<Vec<_>>())",
			this);
		#end
	}

	public function copy():IntMap<T> {
		var out = new IntMap<T>();
		#if macro
		#else
		untyped __rust__("{0}.borrow_mut().h = {1}.borrow().h.clone();", out, this);
		#end
		return out;
	}

	public function toString():String {
		#if macro
		return "{}";
		#else
		return untyped __rust__("format!(\"{:?}\", {0}.borrow().h)", this);
		#end
	}

	public function clear():Void {
		#if macro
		#else
		untyped __rust__("{0}.borrow_mut().h.clear();", this);
		#end
	}
}
