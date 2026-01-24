package sys.io;

import haxe.io.Bytes;

/**
 * Rust target implementation of `sys.io.File`.
 *
 * NOTE: Uses `__rust__` internally (framework-only). Apps should call this API.
 */
class File {
	public static function getContent(path: String): String {
		return untyped __rust__("std::fs::read_to_string({0}.as_str()).unwrap()", path);
	}

	public static function saveContent(path: String, content: String): Void {
		untyped __rust__("{ std::fs::write({0}.as_str(), {1}).unwrap(); }", path, content);
	}

	public static function getBytes(path: String): Bytes {
		return untyped __rust__(
			"{
				let data = std::fs::read({0}.as_str()).unwrap();
				std::rc::Rc::new(std::cell::RefCell::new(hxrt::bytes::Bytes::from_vec(data)))
			}",
			path
		);
	}

	public static function saveBytes(path: String, bytes: Bytes): Void {
		untyped __rust__("{ std::fs::write({0}.as_str(), {1}.borrow().as_slice()).unwrap(); }", path, bytes);
	}
}

