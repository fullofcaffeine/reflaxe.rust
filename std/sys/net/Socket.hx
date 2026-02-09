package sys.net;

import haxe.io.Bytes;
import hxrt.net.SocketHandle;
import rust.HxRef;
import sys.net._SocketIO.SocketInput;
import sys.net._SocketIO.SocketOutput;

/**
	`sys.net.Socket` (Rust target implementation)

	Why
	- The upstream stdlib declares `sys.net.Socket` as `extern`, so sys targets must provide a real
	  TCP socket implementation.

	What
	- Implements basic TCP networking:
	  - `connect`, `bind`, `listen`, `accept`
	  - `peer`, `host`
	  - `setTimeout`, `setBlocking`, `setFastSend`, `shutdown`
	  - `select` (best-effort readiness polling)

	How
	- Socket state lives in the Rust runtime (`hxrt::net::SocketHandle`) and is referenced from Haxe
	  via `HxRef<SocketHandle>` (an `Rc<RefCell<...>>`).
	- `input`/`output` are exposed as properties to avoid storing Rust trait objects inside the
	  generated struct (this keeps generated Rust simpler and warning-free).
**/
class Socket {
	public var input(default, null): haxe.io.Input;
	public var output(default, null): haxe.io.Output;

	/**
		A custom value that can be associated with the socket.

		Note: on this target we store it as `Null<Dynamic>` so it can be `null` by default.
	**/
	public var custom: Null<Dynamic> = null;

	@:allow(sys.net.UdpSocket)
	private var handle: HxRef<SocketHandle>;

	public function new(): Void {
		var h: HxRef<SocketHandle> = untyped __rust__("hxrt::net::socket_new_tcp()");
		handle = h;
		input = new SocketInput(h);
		output = new SocketOutput(h);
	}

	public function close(): Void {
		untyped __rust__("{0}.borrow_mut().close()", handle);
	}

	public function read(): String {
		return input.readAll().toString();
	}

	public function write(content: String): Void {
		output.writeString(content);
	}

	public function connect(host: Host, port: Int): Void {
		untyped __rust__("{0}.borrow_mut().connect({1} as i32, {2} as i32)", handle, host.ip, port);
	}

	public function listen(connections: Int): Void {
		untyped __rust__("{0}.borrow_mut().listen({1} as i32)", handle, connections);
	}

	public function shutdown(read: Bool, write: Bool): Void {
		untyped __rust__(
			"{0}.borrow_mut().shutdown({1} as bool, {2} as bool)",
			handle,
			read,
			write
		);
	}

	public function bind(host: Host, port: Int): Void {
		untyped __rust__("{0}.borrow_mut().bind({1} as i32, {2} as i32)", handle, host.ip, port);
	}

	public function accept(): Socket {
		var h: HxRef<SocketHandle> = untyped __rust__("{0}.borrow_mut().accept()", handle);
		var s: Socket = new Socket();
		s.handle = h;
		s.input = new SocketInput(h);
		s.output = new SocketOutput(h);
		return s;
	}

	public function peer(): {host: Host, port: Int} {
		var info: Array<Int> = untyped __rust__(
			"{
				let (ip, port) = {0}.borrow().peer();
				hxrt::array::Array::<i32>::from_vec(vec![ip, port])
			}",
			handle
		);
		var host: Host = new Host("127.0.0.1");
		untyped host.ip = info[0];
		return {host: host, port: info[1]};
	}

	public function host(): {host: Host, port: Int} {
		var info: Array<Int> = untyped __rust__(
			"{
				let (ip, port) = {0}.borrow().host();
				hxrt::array::Array::<i32>::from_vec(vec![ip, port])
			}",
			handle
		);
		var host: Host = new Host("127.0.0.1");
		untyped host.ip = info[0];
		return {host: host, port: info[1]};
	}

	public function setTimeout(timeout: Float): Void {
		untyped __rust__("{0}.borrow_mut().set_timeout({1} as f64)", handle, timeout);
	}

	public function waitForRead(): Void {
		untyped __rust__(
			"{ let _ = hxrt::net::socket_select(vec![{0}.clone()], vec![], vec![], Some(-1.0)); }",
			handle
		);
	}

	public function setBlocking(b: Bool): Void {
		untyped __rust__("{0}.borrow_mut().set_blocking({1} as bool)", handle, b);
	}

	public function setFastSend(b: Bool): Void {
		untyped __rust__("{0}.borrow_mut().set_fast_send({1} as bool)", handle, b);
	}

	public static function select(
		read: Array<Socket>,
		write: Array<Socket>,
		others: Array<Socket>,
		?timeout: Float
	): {read: Array<Socket>, write: Array<Socket>, others: Array<Socket>} {
		var rh: Array<HxRef<SocketHandle>> = [for (s in read) s.handle];
		var wh: Array<HxRef<SocketHandle>> = [for (s in write) s.handle];
		var oh: Array<HxRef<SocketHandle>> = [for (s in others) s.handle];

		var idxGroups: Array<Array<Int>> = untyped __rust__(
			"{
				let (ri, wi, oi) = hxrt::net::socket_select({0}.to_vec(), {1}.to_vec(), {2}.to_vec(), {3});
				hxrt::array::Array::<hxrt::array::Array<i32>>::from_vec(vec![
					hxrt::array::Array::<i32>::from_vec(ri),
					hxrt::array::Array::<i32>::from_vec(wi),
					hxrt::array::Array::<i32>::from_vec(oi),
				])
			}",
			rh,
			wh,
			oh,
			timeout
		);

		function pick(src: Array<Socket>, idx: Array<Int>): Array<Socket> {
			var out: Array<Socket> = [];
			for (i in idx) out.push(src[i]);
			return out;
		}

		return {
			read: pick(read, idxGroups[0]),
			write: pick(write, idxGroups[1]),
			others: pick(others, idxGroups[2]),
		};
	}
}
