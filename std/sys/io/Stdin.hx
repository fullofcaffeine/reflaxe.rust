package sys.io;

import haxe.io.Bytes;
import haxe.io.Eof;
import hxrt.sys.NativeSys;

/**
 * `sys.io.Stdin` (Rust target)
 *
 * Why
 * - The stock `haxe.io.Input.readBytes` uses `Bytes.getData()` to mutate the target buffer.
 * - On reflaxe.rust, `haxe.io.Bytes` is an `extern` wrapper over a Rust-owned buffer, so we must
 *   fill it through the runtime API instead (`hxrt::bytes::Bytes::set`).
 *
 * What
 * - A `haxe.io.Input` backed by Rust `std::io::stdin()`.
 *
 * How
 * - `readByte` delegates to `hxrt.sys.NativeSys.stdinReadByte()` and converts `-1` to `Eof`.
 * - `readBytes` delegates to `hxrt.sys.NativeSys.stdinReadBytes(...)`, which writes into
 *   runtime `Bytes` storage (`hxrt::bytes::write_from_slice`) and returns `0` on EOF.
 *
 * Notes
 * - This is intentionally minimal (v1 portability). Advanced features like non-blocking reads
 *   and proper error mapping to `haxe.io.Error` can be added later.
 */
class Stdin extends haxe.io.Input {
	public function new() {}

	override public function readByte():Int {
		var c = NativeSys.stdinReadByte();
		if (c < 0)
			throw new Eof();
		return c;
	}

	override public function readBytes(s:Bytes, pos:Int, len:Int):Int {
		if (pos < 0 || len < 0 || pos + len > s.length) {
			throw haxe.io.Error.OutsideBounds;
		}
		if (len == 0)
			return 0;

		return NativeSys.stdinReadBytes(s, pos, len);
	}
}
