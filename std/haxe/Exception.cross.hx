package haxe;

/**
	Base class for exceptions.

	Why
	- The Haxe standard library uses `haxe.Exception` as the base type for user-defined exceptions and
	  for utilities like `sys.thread` pools.
	- Catching `haxe.Exception` is also used as a wildcard catch on some targets.

	What
	- Stores an exception message and optional chaining (`previous`) and `native` payload.
	- Exposes a `stack` field typed as `haxe.CallStack`.

	How
	- This is a minimal, target-local implementation. At the moment `stack` is always empty because
	  `haxe.CallStack` has no native integration on this target yet.
	- The Rust backend's `try/catch` implementation is backed by `hxrt::exception` (panic/unwind),
	  but we still model exceptions as regular Haxe objects for stdlib parity.
**/
@:coreApi
class Exception {
	var __message:String;
	var __previous:Null<Exception>;
	var __native:Any;
	var __stack:Array<haxe.CallStack.StackItem>;

	public var message(get, never):String;

	private function get_message():String
		return __message;

	public var stack(get, never):CallStack;

	private function get_stack():CallStack
		return __stack;

	public var previous(get, never):Null<Exception>;

	private function get_previous():Null<Exception>
		return __previous;

	public var native(get, never):Any;

	final private function get_native():Any {
		return __native;
	}

	static private function caught(value:Any):Exception {
		// Minimal, deterministic semantics:
		// - Avoid `Std.string(value)` because its null checks become untyped-null comparisons on this target.
		// - Keep the thrown value accessible via `.native`.
		return new Exception("Exception", null, value);
	}

	static private function thrown(value:Any):Any {
		return value;
	}

	public function new(message:String, ?previous:Exception, ?native:Any):Void {
		__message = message;
		__previous = previous;
		__native = native;
		__stack = [];
	}

	private function unwrap():Any {
		return __native;
	}

	public function toString():String {
		return __message;
	}

	public function details():String {
		return "Exception: " + toString() + CallStack.toString(stack);
	}
}
