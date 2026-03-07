import rust.adapters.ReflaxeStdAdapters;

class Main {
	static function optionLabel(value:reflaxe.std.Option<Int>):String {
		return switch value {
			case reflaxe.std.Option.Some(v): "some:" + v;
			case reflaxe.std.Option.None: "none";
		};
	}

	static function resultLabel(value:reflaxe.std.Result<Int, String>):String {
		return switch value {
			case reflaxe.std.Result.Ok(v): "ok:" + v;
			case reflaxe.std.Result.Err(e): "err:" + e;
		};
	}

	static function main() {
		var portableOption:reflaxe.std.Option<Int> = reflaxe.std.Option.Some(7);
		var rustOption = ReflaxeStdAdapters.toRustOption(portableOption);
		var roundOption = ReflaxeStdAdapters.fromRustOption(rustOption);
		Sys.println("opt.round=" + optionLabel(roundOption));

		var portableResult:reflaxe.std.Result<Int, String> = reflaxe.std.Result.Err("boom");
		var rustResult = ReflaxeStdAdapters.toRustResult(portableResult);
		var roundResult = ReflaxeStdAdapters.fromRustResult(rustResult);
		Sys.println("res.round=" + resultLabel(roundResult));
	}
}
