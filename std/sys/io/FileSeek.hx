package sys.io;

/**
	`sys.io.FileSeek` (Rust target override)

	Why
	- reflaxe.rust currently emits Rust modules only for user code and for `std/` overrides shipped
	  with this target (see `src/reflaxe/rust/RustCompiler.hx`).
	- `sys.io.FileInput` / `sys.io.FileOutput` expose `seek(p, pos:FileSeek)`, so the enum must be
	  emitted as part of the Rust crate, not just typed from the upstream Haxe std.

	What
	- The standard file seek origin enum used by `sys.io.FileInput` / `sys.io.FileOutput`.

	How
	- Matches the upstream Haxe enum definition exactly.
**/
enum FileSeek {
	SeekBegin;
	SeekCur;
	SeekEnd;
}

