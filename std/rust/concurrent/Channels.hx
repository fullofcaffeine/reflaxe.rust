package rust.concurrent;

import rust.HxRef;
import rust.Option;
import rust.Ref;

/**
	rust.concurrent.Channels

	Why
	- `Channel<T>` is a typed runtime handle. Operations live in this namespace so we keep Haxe
	  callsites typed while avoiding generated wrapper structs.

	What
	- `create()`, `send(...)`, `recv(...)`, `tryRecv(...)`.

	How
	- This is an extern binding to `hxrt::concurrent`; no wrapper class is emitted.
**/
@:native("hxrt::concurrent")
extern class Channels {
	@:native("channel_new")
	public static function create<T>():HxRef<Channel<T>>;

	@:native("channel_send")
	public static function send<T>(channel:Ref<HxRef<Channel<T>>>, value:T):Void;

	@:native("channel_recv")
	public static function recv<T>(channel:Ref<HxRef<Channel<T>>>):T;

	@:native("channel_try_recv")
	public static function tryRecv<T>(channel:Ref<HxRef<Channel<T>>>):Option<T>;
}
