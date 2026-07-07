class Main {
	static function main() {
		var ok:Bool = untyped __rust__("std::fs::metadata(\".\").is_ok()");
		if (!ok) {}
	}
}
