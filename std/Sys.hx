/**
 * Rust target implementation of core `Sys` APIs.
 *
 * Intentionally minimal for now (Milestone 8 acceptance coverage).
 */
class Sys {
	public static function print(v: Dynamic): Void {
		untyped __rust__("{ print!(\"{}\", {0}); }", v);
	}

	public static function println(v: Dynamic): Void {
		untyped __rust__("{ println!(\"{}\", {0}); }", v);
	}

	public static function args(): Array<String> {
		return untyped __rust__("hxrt::array::Array::<String>::from_vec(std::env::args().skip(1).collect::<Vec<String>>())");
	}

	public static function getCwd(): String {
		return untyped __rust__("std::env::current_dir().unwrap().to_string_lossy().to_string()");
	}

	public static function setCwd(path: String): Void {
		untyped __rust__("{ std::env::set_current_dir({0}.as_str()).unwrap(); }", path);
	}

	public static function exit(code: Int): Void {
		untyped __rust__("std::process::exit({0})", code);
	}
}
