@:native("crate::bound_tools::BoundTools")
extern class BoundTools {
	@:rustGeneric("T: std::fmt::Display")
	public static function describe<T>(value:T):String;
}
