package rust.process;

/**
 * A closed failure from the current process's standard-stream boundary.
 *
 * Why
 *
 * Binary protocol helpers need to distinguish invalid caller input from a
 * failed read, write, or flush. They must not depend on platform-specific
 * error strings or expose those strings to an untrusted parent process.
 *
 * What
 *
 * This opaque Rust-native value exposes only four stable categories. It does
 * not contain an OS error message, path, handle, or platform error code.
 *
 * How
 *
 * `CurrentProcess` creates the value at its native `std::io` boundary. Haxe
 * code inspects the exact category through these predicates and returns to
 * ordinary typed control flow immediately.
 */
@:native("crate::current_process_tools::CurrentProcessError")
extern class CurrentProcessError {
	@:native("is_invalid_input")
	public function isInvalidInput():Bool;

	@:native("is_read")
	public function isRead():Bool;

	@:native("is_write")
	public function isWrite():Bool;

	@:native("is_flush")
	public function isFlush():Bool;
}
