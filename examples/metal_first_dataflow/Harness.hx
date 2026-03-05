import rust.Option;
import rust.Result;
import rust.Vec;

private typedef ParsedNumbers = {
	values:Vec<Int>,
	count:Int
};

/**
	Metal-first deterministic harness.

	Why
	- Shows Rust-first authoring patterns in Haxe (`Result`, `Option`, `Vec`) without raw app-side injection.

	What
	- Parses comma-separated ints into a `Vec<Int>`.
	- Computes a deterministic signature with Rust-first collection/control-flow style.

	How
	- Parsing/selection stays in typed Haxe.
	- Uses `Result`/`Option`/`Vec` directly so the entire app layer remains strict-boundary safe.
**/
class Harness {
	public static function runValid():Array<String> {
		return switch (runLines("4, 8, 15, 16, 23, 42")) {
			case Ok(lines):
				lines;
			case Err(error):
				["error=" + error];
		};
	}

	public static function runInvalid():String {
		return switch (runLines("4, oops, 9")) {
			case Ok(lines):
				lines.join("|");
			case Err(error):
				"error=" + error;
		};
	}

	static function runLines(raw:String):Result<Array<String>, String> {
		return switch (parseNumbers(raw)) {
			case Err(error):
				Err(error);
			case Ok(parsed):
				var lines = new Array<String>();
				lines.push("count=" + parsed.count);

				switch (choosePeak(parsed.values.clone())) {
					case Some(value):
						lines.push("peak=" + value);
					case None:
						lines.push("peak=<none>");
				}

				lines.push("sig=" + signature(parsed.values));
				Ok(lines);
		};
	}

	static function parseNumbers(raw:String):Result<ParsedNumbers, String> {
		var parts = raw.split(",");
		if (parts.length == 0) {
			return Err("empty-input");
		}

		var values = new Vec<Int>();
		var count = 0;
		for (part in parts) {
			var token = StringTools.trim(part);
			if (token == "") {
				return Err("empty-token");
			}

			switch (parseSignedInt(token)) {
				case Ok(value):
					values.push(value);
					count++;
				case Err(error):
					return Err(error);
			}
		}

		return Ok({
			values: values,
			count: count
		});
	}

	static function choosePeak(values:Vec<Int>):Option<Int> {
		var peak:Option<Int> = None;
		for (value in values) {
			peak = switch (peak) {
				case None:
					Some(value);
				case Some(existing):
					if (value > existing) Some(value) else Some(existing);
			};
		}
		return peak;
	}

	static function signature(values:Vec<Int>):Int {
		var out = 0x13579bdf;
		for (value in values) {
			out = mix(out, value);
		}
		return out;
	}

	static inline function mix(seed:Int, value:Int):Int {
		var rotated = (seed << 5) | (seed >>> 27);
		return rotated ^ (value * 31);
	}

	static function parseSignedInt(token:String):Result<Int, String> {
		var start = 0;
		var sign = 1;
		if (token.charAt(0) == "-") {
			sign = -1;
			start = 1;
		}
		if (start >= token.length) {
			return Err("invalid-int:" + token);
		}

		var value = 0;
		for (index in start...token.length) {
			switch (digitForChar(token.charAt(index))) {
				case Some(digit):
					value = value * 10 + digit;
				case None:
					return Err("invalid-int:" + token);
			}
		}
		return Ok(sign * value);
	}

	static function digitForChar(value:String):Option<Int> {
		return switch (value) {
			case "0":
				Some(0);
			case "1":
				Some(1);
			case "2":
				Some(2);
			case "3":
				Some(3);
			case "4":
				Some(4);
			case "5":
				Some(5);
			case "6":
				Some(6);
			case "7":
				Some(7);
			case "8":
				Some(8);
			case "9":
				Some(9);
			case _:
				None;
		};
	}
}
