package haxe.ds;

/**
	`haxe.ds.List<T>` (reflaxe.rust)

	Why:
	- Haxe’s macro stdlib and some user code use `haxe.ds.List` as a simple growable collection.
	- The Rust target needs a small, predictable implementation to support common patterns without
	  depending on target-specific behavior.

	What:
	- A **minimal** `List<T>` implementation backed by an `Array<T>`.
	- Provides the core surface needed by most code:
	  - `new()`
	  - `add(x)` (append)
	  - `iterator()`
	  - `length`

	How:
	- Internally stores items in `items:Array<T>`.
	- `length` is maintained explicitly to match the Haxe API and keep codegen straightforward.

	Tradeoffs:
	- This is **not** a linked list; it is intentionally a compact representation that maps well to
	  Rust’s `Vec<T>`.
	- As a result, some algorithms that assume O(1) list appends + cheap node splicing may behave
	  differently; for Rust-targeted code, prefer `Array<T>` for most use-cases.
**/
class List<T> {
	public var length(default, null):Int;

	var items:Array<T>;

	public function new() {
		items = [];
		length = 0;
	}

	public function add(x:T):Void {
		items.push(x);
		length = length + 1;
	}

	public function iterator():Iterator<T> {
		#if macro
		return [].iterator();
		#else
		return untyped __rust__("hxrt::iter::Iter::from_vec({0}.borrow().items.to_vec())", this);
		#end
	}
}
