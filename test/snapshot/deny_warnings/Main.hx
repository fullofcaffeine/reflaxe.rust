using rust.OptionTools;

import rust.MutSliceTools;
import rust.Option;
import rust.Vec;

class Main {
	static function main() {
		// Option/Result helper paths should compile without warnings.
		var o: Option<Int> = Some(1);
		var v = o.unwrapOr(0);
		trace(v);

		// `Null<T>` locals initialized to null and then assigned should not trigger `unused_assignments`
		// or `unused_mut` warnings in the generated crate.
		var x: Null<Int> = null;
		x = 3;
		trace(x != null);

		// Statement-position `if`/`switch` should emit clean Rust control-flow.
		var n = 0;
		if (x != null) n = n + 1;
		switch (n) {
			case 1:
				n = n + 1;
			case _:
				n = n + 2;
		}
		trace(n);

		// Rusty surfaces should not introduce warnings when used from idiomatic output.
		var vec = new Vec<Int>();
		vec.push(1);
		vec.push(2);

		MutSliceTools.with(vec, s -> {
			MutSliceTools.set(s, 1, 5);
		});

		var sum = 0;
		for (i in vec) sum = sum + i;
		trace(sum);
	}
}
