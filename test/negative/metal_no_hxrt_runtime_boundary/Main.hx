@:rustAllowRaw
class Main {
	static function runtimeValue():Int {
		return untyped __rust__("hxrt::dynamic::from(1); 0");
	}

	static function main() {
		var value = runtimeValue();
		if (value == -1) {}
	}
}
