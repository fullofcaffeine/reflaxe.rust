import reflaxe.std.Option;

private enum abstract SourceMapSwitchTag(Int) {
	var First = 1;
	var Second = 2;
	var Third = 3;
}

private class SourceMapGenericBox<T> {
	public final value:T;

	public function new(value:T) {
		this.value = value;
	}

	public function inheritedBlockValue():T {
		return {
			var current = value;
			current;
		};
	}
}

private class SourceMapStringBox extends SourceMapGenericBox<String> {
	public function new(value:String) {
		super(value);
	}
}

class Main {
	static var aliasEffect:Int = 0;

	static function markAliasEffect():Void {
		aliasEffect++;
	}

	static function preserveWholeOption<T>(value:Option<T>, fallback:Option<T>):Option<T> {
		return switch value {
			case Some(_): value;
			case None: fallback;
		};
	}

	static function preserveWholeOptionAfterEffect<T>(value:Option<T>, fallback:Option<T>):Option<T> {
		return switch value {
			case Some(_):
				markAliasEffect();
				value;
			case None: fallback;
		};
	}

	static function preserveWholeIntAfterPayloadUse(value:Option<Int>, fallback:Option<Int>):Option<Int> {
		return switch value {
			case Some(payload):
				aliasEffect += payload;
				value;
			case None: fallback;
		};
	}

	static function preserveWholeOptionWithShadow<T>(value:Option<T>, fallback:Option<T>):Option<T> {
		return switch value {
			case Some(_):
				var value:Option<T> = None;
				value;
			case None: fallback;
		};
	}

	static function preserveGenericTagSwitchAfterEffect(value:SourceMapSwitchTag,
			fallback:SourceMapSwitchTag):SourceMapSwitchTag {
		return switch value {
			case First:
				markAliasEffect();
				value;
			case Second: fallback;
			case _: fallback;
		};
	}

	static function preserveGenericSwitchAfterEffect(value:Int, fallback:Int):Int {
		return switch value {
			case 1:
				markAliasEffect();
				value;
			case _: fallback;
		};
	}

	static function preserveGenericStringSwitchAfterEffect(value:String, fallback:String):String {
		return switch value {
			case "hit":
				markAliasEffect();
				value;
			case _: fallback;
		};
	}

	static function optionValue(value:Option<Int>):Int {
		return switch value {
			case Some(payload): payload;
			case None: -1;
		};
	}

	static function knownSomeBlock(value:Int):Int {
		return cast ({
			var next = value + 1;
			next;
		} : Null<Int>);
	}

	static function applyFunction(callback:(value:Int) -> Int, value:Int):Int {
		return callback(value);
	}

	static function blockFunctionValue(seed:Int):Int {
		return applyFunction({
			var offset = seed;
			(value:Int) -> value + offset;
		}, 2);
	}

	static function main():Void {
		var sourceMapValue = 40;
		sourceMapValue += 2;
		var stagedSourceMap:Int;
		stagedSourceMap = sourceMapValue;
		trace("UTF-8 café");
		trace("source-map-value=" + stagedSourceMap);
		var effectOption = preserveWholeOptionAfterEffect(Some(5), None);
		var payloadOption = preserveWholeIntAfterPayloadUse(Some(5), None);
		var shadowOption = preserveWholeOptionWithShadow(Some(5), Some(7));
		var genericTag = preserveGenericTagSwitchAfterEffect(First, Third);
		var genericValue = preserveGenericSwitchAfterEffect(1, -1);
		var genericString = preserveGenericStringSwitchAfterEffect("hit", "miss");
		trace("source-map-alias=" + aliasEffect + ":" + optionValue(effectOption) + ":" + optionValue(payloadOption) + ":" + optionValue(shadowOption)
			+ ":" + (genericTag == First) + ":" + genericValue + ":" + genericString);
		trace("source-map-known-some=" + knownSomeBlock(4));
		trace("source-map-function=" + blockFunctionValue(3));
		trace("source-map-inherited=" + new SourceMapStringBox("stable").inheritedBlockValue());
	}
}
