package sys.net;

import haxe.io.Bytes;
import haxe.io.Error;
import hxrt.net.NativeSocket;
import hxrt.net.SocketHandle;
import rust.HxRef;

/**
	Internal helpers used by `sys.net.Socket` and `sys.net.UdpSocket`.

	Why
	- Haxe's `sys.net.Socket` API exposes `input`/`output` as `haxe.io.Input` / `haxe.io.Output`.
	- On this target, the actual IO is performed by the Rust runtime via `hxrt::net::SocketHandle`.
	- We keep these wrappers in a shared module so `UdpSocket` can reinitialize `input`/`output`
	  after swapping the underlying socket kind (TCP vs UDP).

	What
	- `SocketInput` implements `haxe.io.Input` over a `SocketHandle`.
	- `SocketOutput` implements `haxe.io.Output` over a `SocketHandle`.

	How
	- Each call forwards through typed helpers in `hxrt.net.NativeSocket`.
	- Bounds checks and EOF semantics follow Haxe expectations.
**/
@:noCompletion
@:dox(hide)
class SocketOutput extends haxe.io.Output {
	private var handle:HxRef<SocketHandle>;

	public function new(handle:HxRef<SocketHandle>) {
		this.handle = handle;
	}

	override public function writeByte(c:Int):Void {
		var b = Bytes.alloc(1);
		b.set(0, c);
		writeBytes(b, 0, 1);
	}

	override public function writeBytes(s:Bytes, pos:Int, len:Int):Int {
		if (pos < 0 || len < 0 || pos + len > s.length)
			throw Error.OutsideBounds;
		if (len == 0)
			return 0;

		return NativeSocket.writeBytes(handle, s, pos, len);
	}

	override public function close():Void {
		super.close();
		NativeSocket.closeHandle(handle);
	}
}

@:noCompletion
@:dox(hide)
class SocketInput extends haxe.io.Input {
	private var handle:HxRef<SocketHandle>;

	public function new(handle:HxRef<SocketHandle>) {
		this.handle = handle;
	}

	override public function readByte():Int {
		var b = Bytes.alloc(1);
		var n = readBytes(b, 0, 1);
		if (n == 0)
			throw new haxe.io.Eof();
		return b.get(0);
	}

	override public function readBytes(s:Bytes, pos:Int, len:Int):Int {
		if (pos < 0 || len < 0 || pos + len > s.length)
			throw Error.OutsideBounds;
		if (len == 0)
			return 0;

		var out:Int = NativeSocket.readBytes(handle, s, pos, len);

		if (out == 0)
			throw new haxe.io.Eof();
		return out;
	}

	override public function close():Void {
		super.close();
		NativeSocket.closeHandle(handle);
	}
}
