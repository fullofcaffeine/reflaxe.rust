package haxe.io;

/**
 * `haxe.io.Encoding` (Rust target override)
 *
 * Why:
 * - `Bytes.ofString` / `Bytes.getString` / `BytesBuffer.addString` accept an optional `Encoding`.
 * - The Rust target currently treats all string/bytes conversions as UTF-8 at runtime, but we still
 *   need the type in order to stay signature-compatible with the standard library and to allow
 *   portable Haxe code to compile unchanged.
 *
 * What:
 * - A minimal `Encoding` enum matching Haxe std: `UTF8` and `RawNative`.
 *
 * How:
 * - The compiler accepts the `encoding` argument but currently evaluates and ignores it.
 * - `RawNative` is kept for API compatibility; it is treated the same as `UTF8` for now.
 */
enum Encoding {
	UTF8;

	/**
		Output the string the way the platform represent it in memory.

		Note: on this Rust target this currently behaves the same as `UTF8`.
	**/
	RawNative;
}

