import reflaxe.std.Option;

class Main {
	static function preserveWholeOption<T>(value:Option<T>, fallback:Option<T>):Option<T> {
		return switch value {
			case Some(_): value;
			case None: fallback;
		};
	}

	static function main():Void {
		var sourceMapValue = 40;
		sourceMapValue += 2;
		var stagedSourceMap:Int;
		stagedSourceMap = sourceMapValue;
		trace("UTF-8 café");
		trace("source-map-value=" + stagedSourceMap);
	}
}
