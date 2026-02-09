package sys.net;

import haxe.io.Bytes;
import haxe.io.Error;
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
	- Each call uses `__rust__` to forward into `hxrt::net::{read_stream,write_stream,close}`.
	- Bounds checks and EOF semantics follow Haxe expectations.
**/
@:noCompletion
@:dox(hide)
class SocketOutput extends haxe.io.Output {
	private var handle: HxRef<SocketHandle>;

	public function new(handle: HxRef<SocketHandle>) {
		this.handle = handle;
	}

	override public function writeByte(c: Int): Void {
		var b = Bytes.alloc(1);
		b.set(0, c);
		writeBytes(b, 0, 1);
	}

	override public function writeBytes(s: Bytes, pos: Int, len: Int): Int {
		if (pos < 0 || len < 0 || pos + len > s.length) throw Error.OutsideBounds;
		if (len == 0) return 0;

		return untyped __rust__(
			"{
				let b = {0}.borrow();
				let data = b.as_slice();
				let start = {1} as usize;
				let end = ({1} + {2}) as usize;
				{3}.borrow_mut().write_stream(&data[start..end]) as i32
			}",
			s,
			pos,
			len,
			handle
		);
	}

	override public function close(): Void {
		super.close();
		untyped __rust__("{0}.borrow_mut().close()", handle);
	}
}

@:noCompletion
@:dox(hide)
class SocketInput extends haxe.io.Input {
	private var handle: HxRef<SocketHandle>;

	public function new(handle: HxRef<SocketHandle>) {
		this.handle = handle;
	}

	override public function readByte(): Int {
		var b = Bytes.alloc(1);
		var n = readBytes(b, 0, 1);
		if (n == 0) throw new haxe.io.Eof();
		return b.get(0);
	}

	override public function readBytes(s: Bytes, pos: Int, len: Int): Int {
		if (pos < 0 || len < 0 || pos + len > s.length) throw Error.OutsideBounds;
		if (len == 0) return 0;

		var out: Int = untyped __rust__(
			"{
				let mut buf = vec![0u8; {2} as usize];
				let n: i32 = {0}.borrow_mut().read_stream(buf.as_mut_slice());
				if n == -1i32 {
					0i32
				} else {
					hxrt::bytes::write_from_slice(&{1}, {3}, &buf[0..(n as usize)]);
					n
				}
			}",
			handle,
			s,
			len,
			pos
		);

		if (out == 0) throw new haxe.io.Eof();
		return out;
	}

	override public function close(): Void {
		super.close();
		untyped __rust__("{0}.borrow_mut().close()", handle);
	}
}

