package sys.net;

import haxe.io.Bytes;
import haxe.io.Error;
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
	- UDP send/recv operations are implemented by calling into `hxrt::net`.
**/
class UdpSocket extends Socket {
	public function new() {
		super();
		var h = untyped __rust__("hxrt::net::socket_new_udp()");
		handle = h;
		input = new SocketInput(h);
		output = new SocketOutput(h);
	}

	override public function bind(host: Host, port: Int): Void {
		untyped __rust__("{0}.borrow_mut().bind({1} as i32, {2} as i32)", handle, host.ip, port);
	}

	public function setBroadcast(b: Bool): Void {
		untyped __rust__("{0}.borrow_mut().udp_set_broadcast({1} as bool)", handle, b);
	}

	public function sendTo(buf: Bytes, pos: Int, len: Int, addr: Address): Int {
		if (pos < 0 || len < 0 || pos + len > buf.length) throw Error.OutsideBounds;
		if (len == 0) return 0;

		return untyped __rust__(
			"{
				let b = {0}.borrow();
				let data = b.as_slice();
				let start = {1} as usize;
				let end = ({1} + {2}) as usize;
				{3}.borrow_mut().udp_send_to(&data[start..end], {4}.borrow().host as i32, {4}.borrow().port as i32) as i32
			}",
			buf,
			pos,
			len,
			handle,
			addr
		);
	}

	public function readFrom(buf: Bytes, pos: Int, len: Int, addr: Address): Int {
		if (pos < 0 || len < 0 || pos + len > buf.length) throw Error.OutsideBounds;
		if (len == 0) return 0;

		var out: Int = untyped __rust__(
			"{
				let mut tmp = vec![0u8; {2} as usize];
				let (n, ip, port) = {0}.borrow_mut().udp_read_from(tmp.as_mut_slice());
				if n == -1i32 {
					0i32
				} else {
					hxrt::bytes::write_from_slice(&{1}, {3}, &tmp[0..(n as usize)]);
					{4}.borrow_mut().host = ip;
					{4}.borrow_mut().port = port;
					n
				}
			}",
			handle,
			buf,
			len,
			pos,
			addr
		);

		if (out == 0) throw new haxe.io.Eof();
		return out;
	}
}
