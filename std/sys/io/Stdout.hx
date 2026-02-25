package sys.io;

import haxe.io.Bytes;
import hxrt.sys.NativeSys;

/**
 * `sys.io.Stdout` (Rust target)
 *
 * Why
 * - Haxe's stock `haxe.io.Output` implementation of `writeBytes` relies on `Bytes.getData()`.
 * - On reflaxe.rust, `haxe.io.Bytes` is an `extern` wrapper over a Rust-owned buffer
 *   (`HxRef<hxrt::bytes::Bytes>`), so `getData()` is not available at runtime.
 * - We therefore provide an explicit output implementation for stdout that can be used by `Sys`
 *   and by portable applications.
 *
 * What
 * - A `haxe.io.Output` backed by Rust `std::io::stdout()`.
 *
 * How
 * - `writeByte` and `writeBytes` delegate to typed runtime helpers in `hxrt::sys`, which operate
 *   on the runtime `Bytes` buffer (`bytes.borrow().as_slice()`) without exposing raw injection
 *   boundaries at this stdlib layer.
 * - Bounds checks are performed in Haxe so behavior matches the `haxe.io.Output` contract.
 */
class Stdout extends haxe.io.Output {
	public function new() {}

	override public function writeByte(c:Int):Void {
		NativeSys.stdoutWriteByte(c);
	}

	override public function writeBytes(s:Bytes, pos:Int, len:Int):Int {
		if (pos < 0 || len < 0 || pos + len > s.length) {
			throw haxe.io.Error.OutsideBounds;
		}
		if (len == 0)
			return 0;

		return NativeSys.stdoutWriteBytes(s, pos, len);
	}

	override public function flush():Void {
		NativeSys.stdoutFlush();
	}
}
