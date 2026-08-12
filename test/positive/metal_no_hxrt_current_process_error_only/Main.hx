import rust.process.CurrentProcessError;

/**
 * Proves that the public error type owns the Rust module named in its native path.
 *
 * This fixture deliberately does not import `CurrentProcess`. A generated signature
 * that mentions only `CurrentProcessError` must still copy and declare the helper.
 */
class Main {
	static function keep(error:CurrentProcessError):CurrentProcessError
		return error;

	static function main():Void {}
}
