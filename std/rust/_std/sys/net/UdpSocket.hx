package sys.net;

import haxe.io.Bytes;
import haxe.io.Error;
import hxrt.net.NativeSocket;
import sys.net._SocketIO.SocketInput;
import sys.net._SocketIO.SocketOutput;

/**
	`sys.net.UdpSocket` (Rust target implementation)

	Why
	- Some Haxe applications use UDP for discovery, telemetry, or lightweight messaging.
	- The upstream `sys.net.UdpSocket` is declared as a class extending `Socket`, so this target
	  needs an implementation consistent with that surface.

	What
	- Provides UDP-specific operations:
	  - `setBroadcast`
	  - `sendTo`
	  - `readFrom`

	How
	- Reuses the base `sys.net.Socket` handle, but initializes it as UDP in `init()`.
	- UDP send/recv operations are implemented through typed helpers in `hxrt.net.NativeSocket`.
**/
class UdpSocket extends Socket {
	public function new() {
		super();
		var h = NativeSocket.newUdp();
		handle = h;
		input = new SocketInput(h);
		output = new SocketOutput(h);
	}

	override public function bind(host:Host, port:Int):Void {
		untyped __rust__("{0}.borrow_mut().bind({1} as i32, {2} as i32)", handle, host.ip, port);
	}

	public function setBroadcast(b:Bool):Void {
		NativeSocket.udpSetBroadcast(handle, b);
	}

	public function sendTo(buf:Bytes, pos:Int, len:Int, addr:Address):Int {
		if (pos < 0 || len < 0 || pos + len > buf.length)
			throw Error.OutsideBounds;
		if (len == 0)
			return 0;

		return NativeSocket.udpSendTo(handle, buf, pos, len, addr.host, addr.port);
	}

	public function readFrom(buf:Bytes, pos:Int, len:Int, addr:Address):Int {
		if (pos < 0 || len < 0 || pos + len > buf.length)
			throw Error.OutsideBounds;
		if (len == 0)
			return 0;

		var readInfo:Array<Int> = NativeSocket.udpReadFrom(handle, buf, pos, len);
		var out:Int = readInfo[0];
		if (out > 0) {
			addr.host = readInfo[1];
			addr.port = readInfo[2];
		}

		if (out == 0)
			throw new haxe.io.Eof();
		return out;
	}
}
