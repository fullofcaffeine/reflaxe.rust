/**
 * Control probe for the existing raw Cargo path-dependency behavior.
 *
 * This compiles because Cargo treats the helper as a separate crate. The path
 * remains ambient input, however: haxe.rust does not copy or bind its source.
 */
@:native("unsafe_support::UnsafeProbe")
@:rustCargo({name: "unsafe_support", path: "../support"})
extern class AmbientUnsafeProbe {
	@:native("read_known_value")
	public static function readKnownValue():Int;
}
