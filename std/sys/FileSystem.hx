package sys;

/**
 * Rust target implementation of `sys.FileSystem`.
 *
 * NOTE: Uses `__rust__` internally (framework-only). Apps should call this API.
 */
class FileSystem {
	public static function exists(path: String): Bool {
		return untyped __rust__("std::path::Path::new({0}.as_str()).exists()", path);
	}

	public static function isDirectory(path: String): Bool {
		return untyped __rust__("std::path::Path::new({0}.as_str()).is_dir()", path);
	}

	public static function createDirectory(path: String): Void {
		untyped __rust__("{ std::fs::create_dir_all({0}.as_str()).unwrap(); }", path);
	}

	public static function deleteFile(path: String): Void {
		untyped __rust__("{ std::fs::remove_file({0}.as_str()).unwrap(); }", path);
	}

	public static function deleteDirectory(path: String): Void {
		untyped __rust__("{ std::fs::remove_dir({0}.as_str()).unwrap(); }", path);
	}

	public static function readDirectory(path: String): Array<String> {
		return untyped __rust__(
			"{
				let mut out: Vec<String> = Vec::new();
				for entry in std::fs::read_dir({0}.as_str()).unwrap() {
					let name = entry.unwrap().file_name().to_string_lossy().to_string();
					out.push(name);
				}
				out
			}",
			path
		);
	}
}

