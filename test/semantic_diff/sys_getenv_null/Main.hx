class Main {
	static function main() {
		var key = "__REFLAXE_RUST_SEMANTIC_DIFF_MISSING_ENV__";
		var value = Sys.getEnv(key);
		Sys.println(value == null ? "null" : value);
	}
}
