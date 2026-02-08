package sys.io;

import haxe.io.Bytes;

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
 * - Implements `writeByte`, `writeBytes`, and `flush` via Rust `std::io::Write`.
 * - Performs bounds checks in Haxe to match `haxe.io.Output` contract.
 */
class Stderr extends haxe.io.Output {
	public function new() {
	}

	override public function writeByte(c: Int): Void {
		untyped __rust__(
			"{
				use std::io::Write;
				std::io::stderr().write_all(&[({0} & 0xFF) as u8]).unwrap();
			}",
			c
		);
	}

	override public function writeBytes(s: Bytes, pos: Int, len: Int): Int {
		if (pos < 0 || len < 0 || pos + len > s.length) {
			throw haxe.io.Error.OutsideBounds;
		}
		if (len == 0) return 0;

		return untyped __rust__(
			"{
				use std::io::Write;
				let b = {0}.borrow();
				let data = b.as_slice();
				let start = {1} as usize;
				let end = ({1} + {2}) as usize;
				std::io::stderr().write_all(&data[start..end]).unwrap();
				{2} as i32
			}",
			s,
			pos,
			len
		);
	}

	override public function flush(): Void {
		untyped __rust__(
			"{
				use std::io::Write;
				std::io::stderr().flush().ok();
			}"
		);
	}
}
