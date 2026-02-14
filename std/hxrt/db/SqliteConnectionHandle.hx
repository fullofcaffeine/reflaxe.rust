package hxrt.db;

/**
	`hxrt.db.SqliteConnectionHandle` (opaque runtime handle)

	Why
	- `sys.db.Sqlite` needs to hold a live `rusqlite::Connection` across calls.
	- Keeping that state in a typed opaque handle avoids storing the connection in untyped value slots.

	What
	- Marker extern for the Rust type `crate::db_sqlite_driver::SqliteConnectionHandle`.

	How
	- This type is never instantiated directly from Haxe.
	- `hxrt.db.NativeSqliteDriver` creates and operates on `HxRef<SqliteConnectionHandle>`.
**/
@:native("crate::db_sqlite_driver::SqliteConnectionHandle")
extern class SqliteConnectionHandle {}
