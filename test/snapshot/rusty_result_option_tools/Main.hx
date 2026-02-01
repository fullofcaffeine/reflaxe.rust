using rust.OptionTools;
using rust.ResultTools;

import rust.Option;
import rust.Result;

class Main {
	static function main() {
		var o: Option<Int> = Some(10);
		var n = o
			.map(function(v: Int): Int return v + 1)
			.andThen(function(v: Int): Option<Int> return (v > 0 ? Some(v * 2) : None))
			.unwrapOr(0);

		// Unwrap helpers (Rust-style).
		var u1 = o.expect("expected a value");
		trace(u1);

		var r: Result<Int, String> = Ok(n);
		var r2 = r
			.mapOk(function(v: Int): Int return v + 5)
			.andThen(function(v: Int): Result<Int, String> return (v > 100 ? Err("too big") : Ok(v)));

		var msg = r2
			.context("computing value")
			.unwrapOrElse(function(_e: String): Int return -1);
		trace(msg);

		var rr: Result<Int, String> = Ok(123);
		trace(rr.unwrap());

		var o2: Option<Int> = None;
		var r3 = o2.okOrElse(function(): String return "missing");
		trace(r3.isErr());

		var caught: Result<Int, String> = ResultTools.catchString(function(): Int {
			var x = 1;
			if (x == 1) throw "boom";
			return x;
		});

		switch (caught) {
			case Ok(v):
				trace(v);
			case Err(e):
				trace(e);
		}
	}
}
