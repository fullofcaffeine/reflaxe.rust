import reflaxe.std.Option;
import reflaxe.std.Result;

class Main {
	static function optionScore(value:Option<Int>):Int {
		return switch value {
			case Some(v): v;
			case None: 0;
		};
	}

	static function resultScore(value:Result<Int, Int>):Int {
		return switch value {
			case Ok(v): v;
			case Err(e): -e;
		};
	}

	static function main() {
		var maybe:Option<Int> = Some(3);
		var fallback:Option<Int> = None;
		var done:Result<Int, Int> = Ok(5);
		var fail:Result<Int, Int> = Err(2);
		var total = optionScore(maybe) + optionScore(fallback) + resultScore(done) + resultScore(fail);
		if (total == -1000) {}
	}
}
