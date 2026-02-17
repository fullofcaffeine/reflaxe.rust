package hxrt.thread;

import sys.thread.Types.ThreadMessage;

/**
	`hxrt.thread.NativeThread` (Rust runtime binding)

	Why
	- `sys.thread.Thread` needs a small set of runtime hooks that return boundary-typed
	  message payloads.
	- Calling these hooks through raw `untyped __rust__` can leave unresolved monomorphs in
	  the typed AST and produce noisy backend warnings in user builds.

	What
	- Typed extern binding to `hxrt::thread` helpers used by `sys.thread.Thread`.

	How
	- `@:native("hxrt::thread")` maps this extern class to the runtime module.
	- Each `@:native(...)` static function maps to one Rust function with a concrete Haxe type.
**/
@:native("hxrt::thread")
extern class NativeThread {
	@:native("thread_read_message")
	public static function readMessage(block:Bool):ThreadMessage;
}
