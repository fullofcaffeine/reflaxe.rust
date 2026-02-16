package sys.db;

import hxrt.db.QueryResultHandle;
import hxrt.db.NativeSqliteDriver;
import hxrt.db.NativeQueryResult;
import hxrt.db.SqliteConnectionHandle;
import rust.HxRef;

/**
	`sys.db.Sqlite` (Rust target override)

	Why
	- Provides a portable entry point for opening SQLite connections on sys targets.
	- Commonly used for small embedded databases or local app state.

	What
	- `open(file)` opens a SQLite database file and returns a `sys.db.Connection`.

	How
	- Uses the `rusqlite` crate behind the scenes.
	- Connection state lives behind `HxRef<hxrt.db.SqliteConnectionHandle>` (typed extern handle).
	- Driver-specific logic (open/close/request/lastInsertId/SQL rendering) lives in
	  `std/sys/db/native/db_sqlite_driver.rs` and is reached through `hxrt.db.NativeSqliteDriver`.
	- Queries are executed synchronously and results are materialized into
	  `hxrt::db::QueryResult` for cursor-style access.
**/
@:rustCargo({name: "rusqlite", version: "0.38", features: ["bundled"]})
@:rustExtraSrc("sys/db/native/db_sqlite_driver.rs")
@:coreApi
class Sqlite {
	public static function open(file:String):Connection {
		return new SqliteConnection(file);
	}
}

private class SqliteConnection implements Connection {
	var handle:HxRef<SqliteConnectionHandle>;

	public function new(file:String) {
		handle = NativeSqliteDriver.openHandle(file);
	}

	public function close():Void {
		NativeSqliteDriver.closeHandle(handle);
	}

	public function request(sql:String):ResultSet {
		var res:HxRef<QueryResultHandle> = NativeSqliteDriver.request(handle, sql);
		return new SqliteResultSet(res);
	}

	public function escape(s:String):String {
		return s.split("'").join("''");
	}

	public function quote(s:String):String {
		// Best-effort parity with other targets: escape single quotes and wrap in `'...'`.
		return "'" + escape(s) + "'";
	}

	public function addValue(sb:StringBuf, v:Dynamic):Void {
		sb.add(NativeSqliteDriver.renderSqlValue(v));
	}

	public function lastInsertId():Int {
		return NativeSqliteDriver.lastInsertId(handle);
	}

	public function dbName():String {
		return "SQLite";
	}

	public function startTransaction():Void {
		request("BEGIN TRANSACTION");
	}

	public function commit():Void {
		request("COMMIT");
	}

	public function rollback():Void {
		request("ROLLBACK");
	}
}

private class SqliteResultSet implements ResultSet {
	public var length(get, null):Int;
	public var nfields(get, null):Int;

	var res:HxRef<QueryResultHandle>;

	public function new(res:HxRef<QueryResultHandle>) {
		this.res = res;
	}

	function get_length():Int {
		return NativeQueryResult.length(res);
	}

	function get_nfields():Int {
		return NativeQueryResult.nfields(res);
	}

	public function hasNext():Bool {
		return NativeQueryResult.hasNext(res);
	}

	public function next():Dynamic {
		return NativeQueryResult.nextRowObject(res);
	}

	public function results():List<Dynamic> {
		var l:List<Dynamic> = new List<Dynamic>();
		while (hasNext()) {
			l.add(next());
		}
		return l;
	}

	public function getResult(n:Int):String {
		return NativeQueryResult.getResult(res, n);
	}

	public function getIntResult(n:Int):Int {
		return NativeQueryResult.getIntResult(res, n);
	}

	public function getFloatResult(n:Int):Float {
		return NativeQueryResult.getFloatResult(res, n);
	}

	public function getFieldsNames():Null<Array<String>> {
		// The upstream API is nullable; return `null` when there are no fields.
		return nfields == 0 ? null : NativeQueryResult.fields(res);
	}
}
