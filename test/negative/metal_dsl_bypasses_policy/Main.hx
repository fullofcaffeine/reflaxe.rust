import rust.metal.Code;

@:rustAllowRaw
@:haxeMetal
class Main {
	static function main():Void {
		var marker:Int = Code.expr("{ let __hx_marker: i32 = 1; __hx_marker }");
		if (marker == -1) {}
	}
}
