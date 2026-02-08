package sys.io;

import haxe.io.Bytes;

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
 * - `writeByte` and `writeBytes` are implemented via `untyped __rust__` and operate directly on
 *   the runtime `Bytes` buffer (`bytes.borrow().as_slice()`), avoiding any `getData()` calls.
 * - Bounds checks are performed in Haxe so behavior matches the `haxe.io.Output` contract.
 */
class Stdout extends haxe.io.Output {
	public function new() {
	}

	override public function writeByte(c: Int): Void {
		untyped __rust__(
			"{
				use std::io::Write;
				std::io::stdout().write_all(&[({0} & 0xFF) as u8]).unwrap();
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
				std::io::stdout().write_all(&data[start..end]).unwrap();
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
				std::io::stdout().flush().ok();
			}"
		);
	}
}
