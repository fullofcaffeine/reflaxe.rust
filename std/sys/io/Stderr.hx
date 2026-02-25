package sys.io;

import haxe.io.Bytes;
import hxrt.sys.NativeSys;

/**
 * `sys.io.Stderr` (Rust target)
 *
 * Why
 * - Same rationale as `sys.io.Stdout`: the stock `haxe.io.Output.writeBytes` relies on
 *   `Bytes.getData()`, which is not available for the Rust target override of `haxe.io.Bytes`.
 *
 * What
 * - A `haxe.io.Output` backed by Rust `std::io::stderr()`.
 *
 * How
 * - Implements `writeByte`, `writeBytes`, and `flush` via typed runtime helpers in `hxrt::sys`.
 * - Performs bounds checks in Haxe to match `haxe.io.Output` contract.
 */
class Stderr extends haxe.io.Output {
	public function new() {}

	override public function writeByte(c:Int):Void {
		NativeSys.stderrWriteByte(c);
	}

	override public function writeBytes(s:Bytes, pos:Int, len:Int):Int {
		if (pos < 0 || len < 0 || pos + len > s.length) {
			throw haxe.io.Error.OutsideBounds;
		}
		if (len == 0)
			return 0;

		return NativeSys.stderrWriteBytes(s, pos, len);
	}

	override public function flush():Void {
		NativeSys.stderrFlush();
	}
}
