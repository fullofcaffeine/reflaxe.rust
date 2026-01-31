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
 * - Those operations are lowered to direct calls/borrows on the runtime type, e.g.:
 *   - `bytes.get(i)` → `bytes.borrow().get(i)`
 *   - `bytes.set(i, v)` → `bytes.borrow_mut().set(i, v)`
 *   - `bytes.toString()` → `bytes.borrow().to_string()`
 *
 * Current limitations (as of the early v1 era):
 * - Only the members listed above are compiler intrinsics today. Other methods are declared for API
 *   compatibility, but will currently fail compilation if used (until the runtime/compiler implement
 *   them).
 * - Bounds checks: the current runtime uses Rust indexing and may panic on out-of-bounds access.
 *   This target now throws a catchable Haxe exception payload (via `hxrt::exception`) instead of
 *   panicking, but the exact thrown value is not yet guaranteed to match other targets’ `haxe.io.Error`
 *   payloads. Prefer catching `Dynamic` for now.
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

	public function getData():BytesData;

	public static function alloc(length:Int):Bytes;
	public static function ofString(s:String, ?encoding:Encoding):Bytes;

	public function get(pos:Int):Int;
	public function set(pos:Int, v:Int):Void;
	public function blit(pos:Int, src:Bytes, srcpos:Int, len:Int):Void;
	public function sub(pos:Int, len:Int):Bytes;
	public function getString(pos:Int, len:Int, ?encoding:Encoding):String;
	public function toString():String;
}
