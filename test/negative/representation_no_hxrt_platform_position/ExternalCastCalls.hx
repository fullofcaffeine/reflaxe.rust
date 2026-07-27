class ExternalCastCalls {
	public function new() {
		// π makes character and UTF-8 byte offsets different before each wrapped call.
		var now = (cast Sys.time : Void->Float)();
		var resolved = (cast Type.resolveClass : String->Class<Dynamic>)("β.ExternalCastCalls");
		var reflected = (cast Reflect.field : Dynamic->String->Dynamic)({value: 1}, "κλειδί");
		if (now == -1 || resolved == null || reflected == null) {}
	}

	static function main():Void {
		new ExternalCastCalls();
	}
}
