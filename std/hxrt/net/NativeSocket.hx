package hxrt.net;

import rust.HxRef;
import rust.Ref;

/**
	Typed native boundary for `sys.net.Socket` operations.

	Why
	- `sys.net.Socket` is a core stdlib API, but the actual socket implementation lives in Rust
	  runtime code (`hxrt::net`).
	- Keeping this bridge typed avoids raw `__rust__` snippets in first-party std overrides and
	  improves metal fallback diagnostics.

	What
	- Exposes TCP socket lifecycle and polling helpers used by `std/sys/net/Socket.cross.hx`.
	- Returns plain typed values (`Int`, `Bool`, `Array<Array<Int>>`) so callers immediately return
	  to normal typed Haxe code.

	How
	- Binds to crate module `socket_native` provided via `@:rustExtraSrc`.
	- Each method maps to a small Rust wrapper function that calls `hxrt::net::SocketHandle` methods.
**/
@:native("crate::socket_native")
@:rustExtraSrc("sys/net/native/socket_native.rs")
extern class NativeSocket {
	@:native("new_tcp")
	public static function newTcp():HxRef<SocketHandle>;

	@:native("new_udp")
	public static function newUdp():HxRef<SocketHandle>;

	@:native("host_resolve")
	public static function hostResolve(name:Ref<String>):Int;

	@:native("host_to_string")
	public static function hostToString(ip:Int):String;

	@:native("host_reverse")
	public static function hostReverse(ip:Int):String;

	@:native("host_local")
	public static function hostLocal():String;

	@:native("close")
	public static function closeHandle(handle:Ref<HxRef<SocketHandle>>):Void;

	public static function connect(handle:Ref<HxRef<SocketHandle>>, host:Int, port:Int):Void;
	public static function listen(handle:Ref<HxRef<SocketHandle>>, connections:Int):Void;
	public static function shutdown(handle:Ref<HxRef<SocketHandle>>, read:Bool, write:Bool):Void;
	public static function bind(handle:Ref<HxRef<SocketHandle>>, host:Int, port:Int):Void;
	public static function accept(handle:Ref<HxRef<SocketHandle>>):HxRef<SocketHandle>;

	@:native("peer_ip")
	public static function peerIp(handle:Ref<HxRef<SocketHandle>>):Int;

	@:native("peer_port")
	public static function peerPort(handle:Ref<HxRef<SocketHandle>>):Int;

	@:native("host_ip")
	public static function hostIp(handle:Ref<HxRef<SocketHandle>>):Int;

	@:native("host_port")
	public static function hostPort(handle:Ref<HxRef<SocketHandle>>):Int;

	@:native("set_timeout")
	public static function setTimeout(handle:Ref<HxRef<SocketHandle>>, timeout:Float):Void;

	@:native("wait_for_read")
	public static function waitForRead(handle:Ref<HxRef<SocketHandle>>):Void;

	@:native("set_blocking")
	public static function setBlocking(handle:Ref<HxRef<SocketHandle>>, blocking:Bool):Void;

	@:native("set_fast_send")
	public static function setFastSend(handle:Ref<HxRef<SocketHandle>>, fastSend:Bool):Void;

	@:native("write_bytes")
	public static function writeBytes(handle:Ref<HxRef<SocketHandle>>, bytes:Ref<haxe.io.Bytes>, pos:Int, len:Int):Int;

	@:native("read_bytes")
	public static function readBytes(handle:Ref<HxRef<SocketHandle>>, bytes:Ref<haxe.io.Bytes>, pos:Int, len:Int):Int;

	@:native("udp_set_broadcast")
	public static function udpSetBroadcast(handle:Ref<HxRef<SocketHandle>>, enabled:Bool):Void;

	@:native("udp_send_to")
	public static function udpSendTo(handle:Ref<HxRef<SocketHandle>>, bytes:Ref<haxe.io.Bytes>, pos:Int, len:Int, host:Int, port:Int):Int;

	@:native("udp_read_from")
	public static function udpReadFrom(handle:Ref<HxRef<SocketHandle>>, bytes:Ref<haxe.io.Bytes>, pos:Int, len:Int):Array<Int>;

	@:native("select_groups")
	public static function selectGroups(read:Ref<Array<HxRef<SocketHandle>>>, write:Ref<Array<HxRef<SocketHandle>>>, others:Ref<Array<HxRef<SocketHandle>>>,
		timeout:Null<Float>):Array<Array<Int>>;
}
