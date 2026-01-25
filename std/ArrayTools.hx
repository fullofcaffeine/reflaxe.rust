/**
	`ArrayTools` (reflaxe.rust)

	Why:
	- Many Haxe codebases rely on `Array<T>`-centric helpers like `find`, `exists`, and `fold`.
	- `Lambda` provides similar helpers for `Iterable<T>`, but some teams prefer explicit `Array` APIs
	  (and avoiding `using Lambda`).

	What:
	- A small, **inline-only** helper surface for `Array<T>`.
	- Designed to inline into simple loops so the Rust backend can codegen without needing runtime
	  `Array` method implementations.

	How:
	- All helpers are `inline` and written in an “inline-safe” style:
	  - no early `return` inside loops (Haxe inliner restriction)
	  - use flags + `break` instead
	- The resulting inlined code uses:
	  - `for (x in arr)` iteration
	  - `Array.push(...)`
	  - basic expressions (`if`, assignments)

	Notes:
	- This file is treated as **non-emitted** by the Rust backend (see compiler rule in
	  `src/reflaxe/rust/RustCompiler.hx`), so calls must inline successfully.
**/
class ArrayTools {
	public static inline function map<A, B>(a:Array<A>, f:(item:A) -> B):Array<B> {
		var out:Array<B> = [];
		for (x in a) out.push(f(x));
		return out;
	}

	public static inline function filter<A>(a:Array<A>, f:(item:A) -> Bool):Array<A> {
		var out:Array<A> = [];
		for (x in a) if (f(x)) out.push(x);
		return out;
	}

	public static inline function exists<A>(a:Array<A>, f:(item:A) -> Bool):Bool {
		var found = false;
		for (x in a) {
			if (f(x)) {
				found = true;
				break;
			}
		}
		return found;
	}

	public static inline function find<A>(a:Array<A>, f:(item:A) -> Bool):Null<A> {
		var found:Null<A> = null;
		var i = 0;
		while (i < a.length) {
			var x:A = a[i];
			if (f(x)) {
				found = x;
				break;
			}
			i++;
		}
		return found;
	}

	public static inline function fold<A, B>(a:Array<A>, f:(item:A, acc:B) -> B, first:B):B {
		for (x in a) first = f(x, first);
		return first;
	}
}
