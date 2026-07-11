@:rustMetal
class Main {
	static function main() {
		var marker:Int = untyped __rust__("{ let __hx_marker: i32 = 1; __hx_marker }");
		if (marker == -1) {}
	}
}
