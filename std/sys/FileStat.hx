package sys;

/**
	`sys.FileStat` (Rust target override)

	Why
	- Haxe declares `sys.FileStat` as a structural typedef returned by `sys.FileSystem.stat`.
	- reflaxe.rust only *emits* Rust modules for user code and for this repo's `std/` overrides.
	  If we rely on the upstream Haxe std typedef, the type may typecheck but no Rust type would
	  exist for `stat()` to return.

	What
	- Structural file metadata used by portable Haxe code.
	- Mirrors the upstream Haxe 4.3.7 field set (gid/uid/atime/mtime/ctime/size/dev/ino/nlink/rdev/mode).

	How
	- `sys.FileSystem.stat(path)` constructs and returns an anonymous object with these fields.
	- Some fields are platform-dependent and may be best-effort:
	  - `gid`, `uid`, `dev`, `ino`, `nlink`, `rdev`, `mode` are derived from `std::fs::Metadata`
	    on Unix via `std::os::unix::fs::MetadataExt`, otherwise default to `0` on non-Unix.
	  - `ctime` uses Rust's `created()` when available; if unavailable, it falls back to `mtime`.
**/
typedef FileStat = {
	var gid: Int;
	var uid: Int;
	var atime: Date;
	var mtime: Date;
	var ctime: Date;
	var size: Int;
	var dev: Int;
	var ino: Int;
	var nlink: Int;
	var rdev: Int;
	var mode: Int;
}

