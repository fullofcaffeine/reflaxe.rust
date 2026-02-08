package sys.io;

import haxe.io.Bytes;
import haxe.io.Eof;

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
 * - `readByte` calls into Rust and returns `-1` on EOF; we convert that to a Haxe `Eof` exception.
 * - `readBytes` reads up to `len` bytes and writes them into `s` via `s.borrow_mut().set(...)`.
 *   It returns `0` on EOF, matching the contract of `haxe.io.Input.readBytes`.
 *
 * Notes
 * - This is intentionally minimal (v1 portability). Advanced features like non-blocking reads
 *   and proper error mapping to `haxe.io.Error` can be added later.
 */
class Stdin extends haxe.io.Input {
	public function new() {
	}

	override public function readByte(): Int {
		var c = untyped __rust__(
			"{
				use std::io::Read;
				let mut buf = [0u8; 1];
				match std::io::stdin().read(&mut buf) {
					Ok(0) => -1i32,
					Ok(_) => buf[0] as i32,
					Err(_) => -1i32,
				}
			}"
		);
		if (c < 0) throw new Eof();
		return c;
	}

	override public function readBytes(s: Bytes, pos: Int, len: Int): Int {
		if (pos < 0 || len < 0 || pos + len > s.length) {
			throw haxe.io.Error.OutsideBounds;
		}
		if (len == 0) return 0;

		return untyped __rust__(
			"{
				use std::io::Read;
				let mut buf = vec![0u8; {2} as usize];
				match std::io::stdin().read(&mut buf) {
					Ok(n) => {
						if n == 0 {
							return 0i32;
						}
						let mut b = {0}.borrow_mut();
						let base = {1} as i32;
						let mut i: usize = 0;
						while i < n {
							b.set(base + i as i32, buf[i] as i32);
							i += 1;
						}
						n as i32
					}
					Err(_) => 0i32,
				}
			}",
			s,
			pos,
			len
		);
	}
}
