class Main {
	static function blowUp():Void {
		var payload:Dynamic = {
			kind: "boom",
			count: 3
		};
		throw payload;
	}

	static function main() {
		try {
			blowUp();
			Sys.println("no-throw");
		} catch (e:Dynamic) {
			Sys.println("caught.kind.has=" + Reflect.hasField(e, "kind"));
			Sys.println("caught.kind=" + Std.string(Reflect.field(e, "kind")));
			Sys.println("caught.count=" + Std.string(Reflect.field(e, "count")));
		}
	}
}
