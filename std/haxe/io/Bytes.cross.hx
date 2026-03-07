package haxe.io;

/**
 * `haxe.io.Bytes` (Rust target override)
 *
 * Why:
 * - The stock Haxe std implementation of `haxe.io.Bytes` assumes a target-specific
 *   internal representation (and often uses `untyped`/inline tricks) to make `get/set`
 *   fast on platforms like JS/HL/C++.
 * - For the Rust target we want a **real Rust-owned buffer** with predictable semantics
 *   and easy interop with the Rust ecosystem (files, networking, crates).
 * - We therefore map `haxe.io.Bytes` to a small Rust runtime type: `hxrt::bytes::Bytes`
 *   (shipped in `runtime/hxrt` and included in every generated Cargo crate).
 *
 * What:
 * - This `Bytes` is declared `extern` so it **does not generate** a Haxe implementation.
 * - In emitted Rust, `haxe.io.Bytes` values are represented as `HxRef<hxrt::bytes::Bytes>`
 *   (currently `type HxRef<T> = Rc<RefCell<T>>`) to match Haxe’s “values are reusable”
 *   semantics even when Rust would otherwise move values.
 *
 * How:
 * - The compiler special-cases a small, high-impact subset of the API so typical stdlib
 *   code continues to work:
 *   - `alloc`, `ofString` (constructors)
 *   - `get`, `set`, `length`, `toString`
 *   - `blit`, `sub`, `getString`
 *   - pure-Haxe numeric/utility helpers layered on top of `get`/`set`
 *     (`fill`, `compare`, `get/setUInt16`, `get/setInt32`, `get/setInt64`,
 *      `get/setFloat`, `get/setDouble`, `ofHex`, `toHex`)
 * - Those operations are lowered to direct calls/borrows on the runtime type, e.g.:
 *   - `bytes.get(i)` → `bytes.borrow().get(i)`
 *   - `bytes.set(i, v)` → `bytes.borrow_mut().set(i, v)`
 *   - `bytes.toString()` → `bytes.borrow().to_string()`
 *
 * Current limitations:
 * - `BytesData`-level escape hatches (`getData`, `ofData`, `fastGet`) are still not backed by a
 *   first-class Rust-target representation. The portable std overrides in this repo avoid relying on
 *   them and use `get`/`set`/`blit` instead.
 * - Bounds checks: the current runtime uses Rust indexing and may panic on out-of-bounds access.
 *   This target now throws a catchable Haxe exception payload (via `hxrt::exception`) instead of
 *   panicking, but the exact thrown value is not yet guaranteed to match other targets’ `haxe.io.Error`
 *   payloads. Prefer catching an untyped payload (`catch (e:Any)`) for now.
 * - String encoding: `toString()` is backed by Rust’s UTF-8 conversion with replacement for invalid
 *   sequences (`from_utf8_lossy`). This matches common expectations for “bytes interpreted as UTF-8”,
 *   but is not identical to every Haxe target’s legacy encoding behavior.
 *
 * Design notes / gotchas:
 * - The `extern` keyword is intentional: if we let the stock std `Bytes` inline into
 *   index operations, it would assume a representation that doesn’t exist for this target.
 * - Interior mutability (`RefCell`) is used so codegen can safely model Haxe’s mutation-heavy
 *   APIs while still compiling to Rust (the borrow checker cannot model arbitrary Haxe aliasing).
 * - When adding new `extern` overrides in `std/`, document:
 *   1) the Rust representation,
 *   2) which members are compiler intrinsics/special-cases,
 *   3) any semantic differences vs other targets.
 *
 * IMPORTANT:
 * - This is `extern` on purpose so the stock std implementation does not inline into
 *   field/index operations that don't exist on the runtime-backed representation.
 * - The compiler special-cases `alloc`, `ofString`, `get`, `set`, `toString`, and `length`.
 */
extern class Bytes {
	public var length(default, null):Int;

	// Internal constructor used by some std classes (e.g. BytesBuffer).
	function new(length:Int, b:BytesData);

	public static function alloc(length:Int):Bytes;
	public static function ofString(s:String, ?encoding:Encoding):Bytes;

	public function get(pos:Int):Int;
	public function set(pos:Int, v:Int):Void;
	public function blit(pos:Int, src:Bytes, srcpos:Int, len:Int):Void;
	public function sub(pos:Int, len:Int):Bytes;
	public function getString(pos:Int, len:Int, ?encoding:Encoding):String;
	public function toString():String;

	public function fill(pos:Int, len:Int, value:Int):Void;
	public function compare(other:Bytes):Int;
	public function getDouble(pos:Int):Float;
	public function getFloat(pos:Int):Float;
	public function setDouble(pos:Int, v:Float):Void;
	public function setFloat(pos:Int, v:Float):Void;
	public function getUInt16(pos:Int):Int;
	public function setUInt16(pos:Int, v:Int):Void;
	public function getInt32(pos:Int):Int;
	public function getInt64(pos:Int):haxe.Int64;
	public function setInt32(pos:Int, v:Int):Void;
	public function setInt64(pos:Int, v:haxe.Int64):Void;

	/**
		Returns the hexadecimal representation of this byte buffer.

		Why
		- Various sys std implementations use `Bytes.toHex()` for SQL blobs, hashes, debugging, etc.
		- The Rust target maps `Bytes` to a runtime-owned buffer (`hxrt::bytes::Bytes`), so we can't
		  rely on the upstream implementation which assumes a target-specific `BytesData`.

		What
		- A pure-Haxe implementation that iterates the bytes and builds the same lowercase
		  hexadecimal string shape as upstream Haxe std.

		How
		- Uses `get(i)` (compiler intrinsic) and emits ASCII hex digits.
		- Kept `inline` so it does not require any additional runtime hooks.
	**/
	public function toHex():String;

	public static function ofHex(s:String):Bytes;
}
