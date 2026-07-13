using rust.OptionTools;

import rust.MutSliceTools;
import rust.Option;
import rust.Vec;

typedef EmptyRecord = {};

class Main {
	static function nullableIndex(values:Array<Null<Int>>, index:Int):Null<Int> {
		return values[index];
	}

	static function main() {
		// Option/Result helper paths should compile without warnings.
		var o:Option<Int> = Some(1);
		var v = o.unwrapOr(0);
		trace(v);

		// `Null<T>` locals initialized to null and then assigned should not trigger `unused_assignments`
		// or `unused_mut` warnings in the generated crate.
		var x:Null<Int> = null;
		x = 3;
		trace(x != null);

		// Statement-position `if`/`switch` should emit clean Rust control-flow.
		var n = 0;
		if (x != null)
			n = n + 1;
		switch (n) {
			case 1:
				n = n + 1;
			case _:
				n = n + 2;
		}
		trace(n);

		// Deferred locals initialized exactly once in each branch should not emit `let mut`.
		// Rust accepts `let branchValue; if (...) branchValue = ... else branchValue = ...;`
		// without mutability, and `#![deny(warnings)]` rejects the unnecessary `mut` form.
		var branchValue:String;
		if (n > 1) {
			branchValue = "wide";
		} else {
			branchValue = "narrow";
		}
		trace(branchValue);

		// Rust-first surfaces should not introduce warnings when used from portable output.
		var vec = new Vec<Int>();
		vec.push(1);
		vec.push(2);

		MutSliceTools.with(vec, s -> {
			MutSliceTools.set(s, 1, 5);
		});

		var sum = 0;
		for (i in vec)
			sum = sum + i;
		trace(sum);

		// Checked indexing of nullable elements should use Rust's native `Option::flatten()` and
		// remain clean under rolling-current Clippy.
		var seven:Null<Int> = 7;
		var nullableValues:Array<Null<Int>> = [seven, null];
		trace(nullableIndex(nullableValues, 0));
		trace(nullableIndex(nullableValues, 1));

		// A zero-field record has no initialization writes and must not acquire/discard a lock guard.
		var empty:EmptyRecord = {};
		trace(empty != null);
	}
}
