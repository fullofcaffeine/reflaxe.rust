package hxrt.db;

/**
	`hxrt.db.NativeSqliteDriver` (typed binding)

	Why
	- `sys.db.Sqlite` needs a Rust-specific constructor helper (`rusqlite::Connection::open`).
	- Keeping that helper in a typed extern avoids raw `untyped __rust__` in high-level std code.

	What
	- Exposes `openHandle(file)` which returns the opaque SQLite connection handle.

	How
	- Binds to the extra Rust module `crate::db_sqlite_driver` (shipped via `@:rustExtraSrc`).
**/
@:native("crate::db_sqlite_driver")
extern class NativeSqliteDriver {
	@:native("open_handle")
	public static function openHandle(file: String): Dynamic;
}
