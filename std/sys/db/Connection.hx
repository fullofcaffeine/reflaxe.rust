package sys.db;

/**
	`sys.db.Connection` (Rust target override)

	Why
	- `sys.db.*` provides a small, cross-target database API used by Haxe sys targets.
	- Libraries often target `sys.db.Connection` so they can work across Neko/HL/C++ and others.

	What
	- A minimal, synchronous connection interface:
	  - `request(sql)` executes a query and returns a cursor-like `ResultSet`.
	  - quoting helpers (`escape`, `quote`, `addValue`) to build SQL strings safely-ish.
	  - transaction helpers (`startTransaction`, `commit`, `rollback`).

	How
	- On the Rust target, concrete implementations live in `std/sys/db/Sqlite.hx` and `std/sys/db/Mysql.hx`.
	- The implementation uses Rust drivers (`rusqlite`, `mysql`) behind the scenes, but the public API
	  stays Haxe-shaped for portability.
**/
interface Connection {
	function request(s:String):ResultSet;
	function close():Void;
	function escape(s:String):String;
	function quote(s:String):String;
	function addValue(s:StringBuf, v:Dynamic):Void;
	function lastInsertId():Int;
	function dbName():String;
	function startTransaction():Void;
	function commit():Void;
	function rollback():Void;
}

