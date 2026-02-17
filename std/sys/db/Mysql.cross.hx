package sys.db;

import hxrt.db.QueryResultHandle;
import hxrt.db.NativeMysqlDriver;
import hxrt.db.NativeQueryResult;
import hxrt.db.MysqlConnectionHandle;
import rust.HxRef;
import sys.db.Types.ResultRow;
import sys.db.Types.SqlValue;

/**
	`sys.db.Mysql` (Rust target override)

	Why
	- Haxe ships a small synchronous MySQL API in `sys.db.*` for sys targets.
	- A lot of existing Haxe code expects `sys.db.Mysql.connect(...)` to exist when targeting
	  a native/sys backend (Neko/HL/C++ etc).

	What
	- `connect(params)` opens a MySQL connection and returns a `sys.db.Connection`.
	- Implements the `Connection` contract using the same runtime cursor container as SQLite:
	  results are materialized into `hxrt::db::QueryResult`, and rows are exposed as `ResultRow`.

	How
	- Uses the Rust `mysql` crate behind the scenes.
	- Connection state lives behind `HxRef<hxrt.db.MysqlConnectionHandle>` (typed extern handle).
	- Driver-specific logic (open/close/request/SQL rendering) lives in
	  `std/sys/db/native/db_mysql_driver.rs` and is reached through `hxrt.db.NativeMysqlDriver`.
	- Queries are executed synchronously. The first result-set is materialized; multi-result
	  statements are not supported yet.
	- Row values are converted into Haxe-friendly row values:
	  - `NULL` -> `null`
	  - integers -> `Int` (clamped to 32-bit)
	  - floats -> `Float`
	  - bytes -> `String` (lossy UTF-8), falling back to `haxe.io.Bytes` if the data is not UTF-8
	  - date/time -> `String` (stable formatting; full `Date` objects can be added later if needed)
**/
// Use `defaultFeatures: false` only if we need to avoid native-tls/openssl in CI.
// For now, keep defaults and tighten once we confirm the feature matrix we want.

@:rustCargo({name: "mysql", version: "27"})
@:rustExtraSrc("sys/db/native/db_mysql_driver.rs")
@:coreApi
class Mysql {
	public static function connect(params:{
		host:String,
		?port:Int,
		user:String,
		pass:String,
		?socket:String,
		?database:String
	}):sys.db.Connection {
		return new MysqlConnection(params);
	}
}

private class MysqlConnection implements Connection {
	var handle:HxRef<MysqlConnectionHandle>;

	public function new(params:{
		host:String,
		?port:Int,
		user:String,
		pass:String,
		?socket:String,
		?database:String
	}) {
		var port:Int = params.port == null ? 3306 : (params.port : Int);
		var host:String = params.host;
		var user:String = params.user;
		var pass:String = params.pass;
		var socket:Null<String> = params.socket;
		var database:Null<String> = params.database;
		handle = NativeMysqlDriver.openHandle(host, user, pass, port, socket, database);
	}

	public function close():Void {
		NativeMysqlDriver.closeHandle(handle);
	}

	public function request(sql:String):ResultSet {
		var res:HxRef<QueryResultHandle> = NativeMysqlDriver.request(handle, sql);
		return new MysqlResultSet(res);
	}

	public function escape(s:String):String {
		// Best-effort MySQL escaping for quoted strings.
		// Prefer parameterized queries in application code when possible.
		return s.split("\\").join("\\\\").split("'").join("\\'");
	}

	public function quote(s:String):String {
		return "'" + escape(s) + "'";
	}

	public function addValue(sb:StringBuf, v:SqlValue):Void {
		sb.add(NativeMysqlDriver.renderSqlValue(v));
	}

	public function lastInsertId():Int {
		return request("SELECT LAST_INSERT_ID()").getIntResult(0);
	}

	public function dbName():String {
		return "MySQL";
	}

	public function startTransaction():Void {
		request("START TRANSACTION");
	}

	public function commit():Void {
		request("COMMIT");
	}

	public function rollback():Void {
		request("ROLLBACK");
	}
}

private class MysqlResultSet implements ResultSet {
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

	public function next():ResultRow {
		return NativeQueryResult.nextRowObject(res);
	}

	public function results():List<ResultRow> {
		var l:List<ResultRow> = new List<ResultRow>();
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
		return nfields == 0 ? null : NativeQueryResult.fields(res);
	}
}
