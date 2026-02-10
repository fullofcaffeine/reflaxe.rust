/**
	`StringBuf` (reflaxe.rust std override)

	Why
	- The upstream `StringBuf` uses `b += x` which becomes an assign-op on a field.
	- The Rust backend currently does not support assign-op field lvalues for non-Copy types.
	- `StringBuf` appears in public APIs (e.g. `sys.db.Connection.addValue`) and is widely used
	  throughout the stdlib, so we need a backend-friendly implementation.

	What
	- A compatible `StringBuf` implementation with the same public surface as upstream:
	  `add`, `addChar`, `addSub`, `length`, and `toString`.

	How
	- Keeps a single `String` buffer field and updates it using plain assignment:
	  `b = b + ...` (no `+=`).
	- Converts `add<T>` arguments through `Std.string` after first boxing to `Dynamic` so we avoid
	  generic type-parameter formatting constraints in Rust codegen.
**/
class StringBuf {
	var b:String;

	/**
		The length of `this` StringBuf in characters.
	**/
	public var length(get, never):Int;

	public function new() {
		b = "";
	}

	inline function get_length():Int {
		return b.length;
	}

	public function add(x:Dynamic):Void {
		b = b + Std.string(x);
	}

	public function addChar(c:Int):Void {
		b = b + String.fromCharCode(c);
	}

	public function addSub(s:String, pos:Int, ?len:Int):Void {
		b = b + (len == null ? s.substr(pos) : s.substr(pos, len));
	}

	public function toString():String {
		return b;
	}
}
