package hxrt.db;

/**
	`hxrt.db.MysqlConnectionHandle` (opaque runtime handle)

	Why
	- `sys.db.Mysql` needs to keep a live `mysql::Conn` between method calls.
	- Holding that connection behind a typed handle avoids storing DB state in untyped value slots.

	What
	- Marker extern for `crate::db_mysql_driver::MysqlConnectionHandle`.

	How
	- The Rust extra-src module owns allocation/lifecycle.
	- Haxe only keeps `HxRef<MysqlConnectionHandle>` and calls typed extern helpers.
**/
@:native("crate::db_mysql_driver::MysqlConnectionHandle")
extern class MysqlConnectionHandle {}
