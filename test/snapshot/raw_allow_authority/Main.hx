@:rustAllowRaw
class Main {
	static function main() {
		var base = 2;
		var direct:Int = untyped __rust__("1");
		var interpolated:Int = reflaxe.rust.macros.RustInjection.__rust__("{0} + 1", base);
		trace(direct + interpolated);
	}
}
