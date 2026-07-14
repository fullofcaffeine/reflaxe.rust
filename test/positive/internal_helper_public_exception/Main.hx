@:rustAllowRaw
class Main {
	static function main():Void {
		var value:Int = reflaxe.rust.macros.RustInjection.__rust__("1i32");
		trace(value);
	}
}
