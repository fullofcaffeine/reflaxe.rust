import rust.metal.Code;

class Main {
	static function main():Void {
		var n:Int = Code.expr("40 + {0}", 2);
		Code.stmt("let _ = {0};", n);
		trace(n);
	}
}
