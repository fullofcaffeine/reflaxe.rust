package hxrt.db;

/**
	`hxrt.db.NativeMysqlDriver` (typed binding)

	Why
	- `sys.db.Mysql` needs target-specific connection setup via `mysql::OptsBuilder`.
	- A typed extern keeps the std override mostly pure Haxe and avoids raw injection callsites.

	What
	- Exposes `openHandle(...)` that returns the opaque MySQL connection handle.

	How
	- Binds to the extra Rust module `crate::db_mysql_driver` (shipped via `@:rustExtraSrc`).
**/
@:native("crate::db_mysql_driver")
extern class NativeMysqlDriver {
	@:native("open_handle")
	public static function openHandle(
		host: String,
		user: String,
		pass: String,
		port: Int,
		socket: Null<String>,
		database: Null<String>
	): Dynamic;
}
