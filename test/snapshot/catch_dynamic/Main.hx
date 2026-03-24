class Main {
	static function main():Void {
		var x = try {
			var payload:Dynamic = {
				kind: "boom",
				count: 3
			};
			throw payload;
			1;
		} catch (e:Dynamic) {
			trace(Reflect.hasField(e, "kind"));
			trace(Reflect.field(e, "kind"));
			trace(Reflect.field(e, "count"));
			2;
		}
		trace(x);
	}
}
