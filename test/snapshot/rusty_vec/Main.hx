using rust.OptionTools;

import rust.IterTools;
import rust.Vec;
import rust.VecTools;
import rust.Option;
import rust.Result;
import rust.Borrow;

class Main {
	static function isEven(n: Int): Bool {
		return (n / 2) * 2 == n;
	}

	static function parseEven(n: Int): Result<Int, String> {
		return isEven(n) ? Ok(n) : Err("odd");
	}

	static function main() {
		var v = new Vec<Int>();
		v.push(1);
		v.push(2);

		trace(VecTools.len(v));

		var last: Option<Int> = v.pop();
		switch (last) {
			case Some(x):
				trace(x);
			case None:
				trace(-1);
		}

		switch (parseEven(2)) {
			case Ok(x):
				trace(x);
			case Err(e):
				trace(e);
		}

		var v2 = new Vec<Int>();
		v2.push(10);
		v2.push(20);

		var sum = 0;
		for (x in IterTools.fromVec(v2.clone())) sum = sum + x;
		trace(sum);

		// Borrow-first element access helpers.
		Borrow.withRef(v2, vr -> {
			var first = VecTools.getRef(vr, 0);
			trace(first.isSome());
		});
	}
}
