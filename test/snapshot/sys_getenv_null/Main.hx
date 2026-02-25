class Main {
	static inline final MISSING_KEY = "__REFLAXE_RUST_MISSING_ENV__";
	static inline final PRESENT_KEY = "__REFLAXE_RUST_PRESENT_ENV__";

	static function main():Void {
		Sys.putEnv(MISSING_KEY, null);
		var missing = Sys.getEnv(MISSING_KEY);
		Sys.println(missing == null ? "<null>" : missing);

		Sys.putEnv(PRESENT_KEY, "present-value");
		var present = Sys.getEnv(PRESENT_KEY);
		Sys.println(present == null ? "<null>" : present);
		Sys.putEnv(PRESENT_KEY, null);
	}
}
