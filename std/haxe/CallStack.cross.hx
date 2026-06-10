package haxe;

/**
	Elements returned by `CallStack` methods.

	Note: this target currently provides a minimal implementation to satisfy stdlib APIs. A richer
	stack trace integration can be implemented later by wiring Rust backtraces into `hxrt`.
**/
enum StackItem {
	CFunction;
	Module(m:String);
	FilePos(s:Null<StackItem>, file:String, line:Int, ?column:Int);
	Method(classname:Null<String>, method:String);
	LocalFunction(?v:Int);
}

/**
	Get information about the call stack.

	Why
	- `haxe.Exception.stack` and various debug utilities depend on `haxe.CallStack`.
	- Threaded std APIs (and user code) frequently surface exceptions across async boundaries.

	What
	- Defines the `CallStack` abstract and the `StackItem` enum used by the stdlib.

	How
	- For now, `callStack()` and `exceptionStack()` return empty arrays (no native stack integration).
	- This keeps the public API stable while allowing future enhancement.
**/
@:allow(haxe.Exception)
@:using(haxe.CallStack)
abstract CallStack(Array<StackItem>) from Array<StackItem> {
	public var length(get, never):Int;

	inline function get_length():Int
		return this.length;

	public static function callStack():Array<StackItem> {
		return [];
	}

	public static function exceptionStack(_fullStack:Bool = false):Array<StackItem> {
		return [];
	}

	static public function toString(_stack:CallStack):String {
		// Minimal implementation: no native stack integration yet.
		// Keep this deterministic and avoid relying on `StringBuf` (which is frequently inlined).
		return "";
	}

	/**
		Format a `haxe.Exception` for `Exception.toString()`.

		Why
		- Upstream `haxe.Exception` delegates to `CallStack.exceptionToString(...)`, so this helper is
		  part of the observable exception-string contract even though it is package-private.
		- Keeping the argument typed as `Exception` avoids a broad `Dynamic` boundary in core std code
		  and preserves access to `toString()` plus `stack`.

		What
		- Produces the deterministic Rust-target exception prefix plus the exception message and stack
		  string.
		- `CallStack.toString(...)` is currently empty because native stack integration is not wired
		  yet, but the call is intentional so future stack support automatically flows through.

		How
		- Concatenates `"Exception: "`, `e.toString()`, and `CallStack.toString(e.stack)`.
		- Do not relax this to `Dynamic`; callers that have a dynamic payload should first convert or
		  wrap it as a `haxe.Exception`.
	**/
	static function exceptionToString(e:Exception):String {
		return "Exception: " + e.toString() + CallStack.toString(e.stack);
	}

	public function subtract(_stack:CallStack):CallStack {
		return this;
	}

	public inline function copy():CallStack {
		return this.copy();
	}

	@:arrayAccess public inline function get(index:Int):StackItem {
		return this[index];
	}

	inline function asArray():Array<StackItem> {
		return this;
	}

	// Keep `itemToString` intentionally unimplemented until we have native stack support.
}
