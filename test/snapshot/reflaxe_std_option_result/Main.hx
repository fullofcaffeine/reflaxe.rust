import reflaxe.std.Option;
import reflaxe.std.Result;

class Main {
	static function optionLabel(value:Option<Int>):String {
		return switch value {
			case Some(v): "some:" + v;
			case None: "none";
		};
	}

	static function resultLabel(value:Result<Int, String>):String {
		return switch value {
			case Ok(v): "ok:" + v;
			case Err(e): "err:" + e;
		};
	}

	static function main() {
		var maybe:Option<Int> = Some(3);
		var done:Result<Int, String> = Ok(5);
		var fail:Result<Int, String> = Err("boom");

		Sys.println(optionLabel(maybe));
		Sys.println(resultLabel(done));
		Sys.println(resultLabel(fail));
	}
}
