package hxrt.db;

import rust.HxRef;
import rust.Ref;

/**
	`hxrt.db.NativeSqliteDriver` (typed binding)

	Why
	- `sys.db.Sqlite` needs Rust-side operations that depend on `rusqlite`.
	- Keeping those operations behind typed externs avoids raw `untyped __rust__` in high-level std code.

	What
	- Typed bridge for opening/closing a connection, executing queries, and rendering SQL literals.

	How
	- Binds to the extra Rust module `crate::db_sqlite_driver` (shipped via `@:rustExtraSrc`).
**/
@:native("crate::db_sqlite_driver")
extern class NativeSqliteDriver {
	@:native("open_handle")
	public static function openHandle(file:String):HxRef<SqliteConnectionHandle>;

	@:native("close_handle")
	public static function closeHandle(handle:Ref<HxRef<SqliteConnectionHandle>>):Void;

	@:native("request")
	public static function request(handle:Ref<HxRef<SqliteConnectionHandle>>, sql:Ref<String>):HxRef<QueryResultHandle>;

	@:native("last_insert_id")
	public static function lastInsertId(handle:Ref<HxRef<SqliteConnectionHandle>>):Int;

	/**
		Why
		- `sys.db.Connection.addValue` is defined upstream as `addValue(sb, v:Dynamic)`.

		How
		- Keep `Dynamic` only at this required boundary and delegate immediately to Rust for
		  deterministic SQL literal rendering.
	**/
	@:native("render_sql_value")
	public static function renderSqlValue(v:Dynamic):String;
}
