package haxe.io;

/**
 * `haxe.io.Eof` (Rust target override)
 *
 * Why
 * - Many `haxe.io.Input` implementations signal end-of-stream by throwing `Eof`.
 * - reflaxe.rust’s runtime models exceptions explicitly (`hxrt::exception`), so we need the type
 *   to exist and be constructible in generated Rust.
 *
 * What
 * - A lightweight exception type thrown when no more input is available.
 *
 * How
 * - This mirrors the upstream Haxe std type: it is a regular class with a trivial constructor and
 *   a small `toString()` for debugging.
 */
class Eof {
	public function new() {}

	@:ifFeature("haxe.io.Eof.*")
	function toString() {
		return "Eof";
	}
}

