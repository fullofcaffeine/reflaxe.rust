package hxrt.db;

import rust.HxRef;
import rust.Ref;

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
	public static function openHandle(host:String, user:String, pass:String, port:Int, socket:Null<String>, database:Null<String>):HxRef<MysqlConnectionHandle>;

	@:native("close_handle")
	public static function closeHandle(handle:Ref<HxRef<MysqlConnectionHandle>>):Void;

	@:native("request")
	public static function request(handle:Ref<HxRef<MysqlConnectionHandle>>, sql:Ref<String>):HxRef<QueryResultHandle>;

	/**
		Why
		- `sys.db.Connection.addValue` is fixed by upstream API as `addValue(sb, v:Dynamic)`.

		How
		- Keep `Dynamic` at this boundary only; convert to SQL text in Rust immediately.
	**/
	@:native("render_sql_value")
	public static function renderSqlValue(v:Dynamic):String;
}
