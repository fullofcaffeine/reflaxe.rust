import haxe.ds.List;

/**
	`Lambda` (reflaxe.rust)

	Why:
	- Haxe’s own compiler (macro stdlib) and many user codebases rely on `using Lambda` for small,
	  readable collection transforms (`arr.map(...)`, `arr.find(...)`, ...).
	- The Rust backend currently keeps the `Iterator<T>` surface minimal and focuses on reliable
	  lowering of `for (x in iterable)` loops.

	What:
	- A *compile-time* (inline) `Lambda` implementation that expands into plain Haxe loops.
	- This file is intentionally treated as **non-emitted** by the Rust backend (see compiler rule
	  in `src/reflaxe/rust/RustCompiler.hx`), so calls must inline successfully.

	How:
	- All helpers are `inline` and written in an “inline-safe” style:
	  - no early `return` inside loops (Haxe inliner restriction)
	  - use flags + `break` instead
	- The resulting inlined code relies only on `for (...)` and basic Array operations, which the
	  backend already supports well.

	Notes:
	- Helpers that produce `List<T>` are provided for macro-time compatibility, but `haxe.ds.List`
	  itself is not yet part of the Rust std surface. Prefer `Array<T>` results in Rust-targeted code.
**/
class Lambda {
	public static inline function array<A>(it:Iterable<A>):Array<A> {
		var a:Array<A> = [];
		for (x in it) a.push(x);
		return a;
	}

	public static inline function list<A>(it:Iterable<A>):List<A> {
		var l = new List<A>();
		for (x in it) l.add(x);
		return l;
	}

	public static inline function map<A, B>(it:Iterable<A>, f:(item:A) -> B):Array<B> {
		var out:Array<B> = [];
		for (x in it) out.push(f(x));
		return out;
	}

	public static inline function mapi<A, B>(it:Iterable<A>, f:(index:Int, item:A) -> B):Array<B> {
		var out:Array<B> = [];
		var i = 0;
		for (x in it) {
			out.push(f(i, x));
			i++;
		}
		return out;
	}

	public static inline function flatten<A>(it:Iterable<Iterable<A>>):Array<A> {
		var out:Array<A> = [];
		for (e in it) for (x in e) out.push(x);
		return out;
	}

	public static inline function flatMap<A, B>(it:Iterable<A>, f:(item:A) -> Iterable<B>):Array<B> {
		return flatten(map(it, f));
	}

	public static inline function has<A>(it:Iterable<A>, elt:A):Bool {
		var found = false;
		for (x in it) {
			if (x == elt) {
				found = true;
				break;
			}
		}
		return found;
	}

	public static inline function exists<A>(it:Iterable<A>, f:(item:A) -> Bool):Bool {
		var found = false;
		for (x in it) {
			if (f(x)) {
				found = true;
				break;
			}
		}
		return found;
	}

	public static inline function foreach<A>(it:Iterable<A>, f:(item:A) -> Bool):Bool {
		var ok = true;
		for (x in it) {
			if (!f(x)) {
				ok = false;
				break;
			}
		}
		return ok;
	}

	public static inline function iter<A>(it:Iterable<A>, f:(item:A) -> Void):Void {
		for (x in it) f(x);
	}

	public static inline function filter<A>(it:Iterable<A>, f:(item:A) -> Bool):Array<A> {
		var out:Array<A> = [];
		for (x in it) if (f(x)) out.push(x);
		return out;
	}

	public static inline function fold<A, B>(it:Iterable<A>, f:(item:A, result:B) -> B, first:B):B {
		for (x in it) first = f(x, first);
		return first;
	}

	public static inline function foldi<A, B>(it:Iterable<A>, f:(item:A, result:B, index:Int) -> B, first:B):B {
		var i = 0;
		for (x in it) {
			first = f(x, first, i);
			i++;
		}
		return first;
	}

	/**
		Counts the number of elements in `it`.

		Why:
		- This is a very common helper in Haxe codebases (`arr.count()` via `using Lambda`).
		- On this target, optional arguments and `Null<T>` lower to idiomatic Rust `Option<T>`, so we
		  can support the stock Haxe signature without escape-hatches.

		What:
		- When `pred` is omitted (or `null`), returns the total number of items in `it`.
		- When `pred` is provided, counts only items where `pred(item)` returns `true`.

		How:
		- The optional predicate is typed as `Null<(item:A)->Bool>` so the backend can represent it as
		  `Option<Rc<dyn Fn(...) -> ...>>`.
		- Codegen relies on two core lowerings:
		  - `pred == null` becomes `pred.is_none()` (no `PartialEq` bound required)
		  - `pred(x)` becomes `pred.as_ref().unwrap()(x)` inside the non-null branch
	**/
	public static inline function count<A>(it:Iterable<A>, ?pred:Null<(item:A) -> Bool>):Int {
		var n = 0;
		if (pred == null) {
			for (_ in it) n++;
		} else {
			for (x in it) if (pred(x)) n++;
		}
		return n;
	}

	public static inline function empty<T>(it:Iterable<T>):Bool {
		var isEmpty = true;
		for (_ in it) {
			isEmpty = false;
			break;
		}
		return isEmpty;
	}

	public static inline function indexOf<T>(it:Iterable<T>, v:T):Int {
		var i = 0;
		var found = false;
		for (x in it) {
			if (x == v) {
				found = true;
				break;
			}
			i++;
		}
		return found ? i : -1;
	}

	public static inline function find<T>(it:Iterable<T>, f:(item:T) -> Bool):Null<T> {
		var found:Null<T> = null;
		for (x in it) {
			if (f(x)) {
				found = x;
				break;
			}
		}
		return found;
	}

	public static inline function findIndex<T>(it:Iterable<T>, f:(item:T) -> Bool):Int {
		var i = 0;
		var found = false;
		for (x in it) {
			if (f(x)) {
				found = true;
				break;
			}
			i++;
		}
		return found ? i : -1;
	}

	public static inline function concat<T>(a:Iterable<T>, b:Iterable<T>):Array<T> {
		var out:Array<T> = [];
		for (x in a) out.push(x);
		for (x in b) out.push(x);
		return out;
	}
}
