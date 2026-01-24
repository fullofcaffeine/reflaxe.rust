package rust.serde;

/**
 * Framework-level Serde JSON helpers.
 *
 * Apps/examples should stay "pure Haxe" (no direct `__rust__` calls).
 * Keep escape hatches in `std/` behind typed APIs.
 */
@:rustCargo({ name: "serde", version: "1", features: ["derive"] })
@:rustCargo({ name: "serde_json", version: "1" })
class SerdeJson {
	@:rustGeneric("T: serde::Serialize")
	public static function toString<T>(value: T): String {
		// Most Haxe class instances compile to `HxRef<T>`; serialize the inner `T` via a borrow.
		return untyped __rust__("serde_json::to_string(&*{0}.borrow()).unwrap()", value);
	}
}
