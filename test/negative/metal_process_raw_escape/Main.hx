class Main {
	static function main() {
		var ok:Bool = untyped __rust__("std::process::Command::new(\"rustc\").arg(\"--version\").status().is_ok()");
		if (!ok) {}
	}
}
