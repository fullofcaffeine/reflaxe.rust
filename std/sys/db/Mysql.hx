package sys.db;

import hxrt.db.QueryResultHandle;
import hxrt.db.NativeMysqlDriver;
import hxrt.db.NativeQueryResult;
import rust.HxRef;

/**
	`sys.db.Mysql` (Rust target override)

	Why
	- Haxe ships a small synchronous MySQL API in `sys.db.*` for sys targets.
	- A lot of existing Haxe code expects `sys.db.Mysql.connect(...)` to exist when targeting
	  a native/sys backend (Neko/HL/C++ etc).

	What
	- `connect(params)` opens a MySQL connection and returns a `sys.db.Connection`.
	- Implements the `Connection` contract using the same runtime cursor container as SQLite:
	  results are materialized into `hxrt::db::QueryResult`, and rows are exposed as `Dynamic`.

	How
	- Uses the Rust `mysql` crate behind the scenes.
	- The connection is stored as a `Dynamic` handle containing:
	  `Arc<Mutex<Option<mysql::Conn>>>`, so `close()` can drop it safely and idempotently.
	- Queries are executed synchronously. The first result-set is materialized; multi-result
	  statements are not supported yet.
	- Row values are converted into Haxe-friendly `Dynamic` values:
	  - `NULL` -> `null`
	  - integers -> `Int` (clamped to 32-bit)
	  - floats -> `Float`
	  - bytes -> `String` (lossy UTF-8), falling back to `haxe.io.Bytes` if the data is not UTF-8
	  - date/time -> `String` (stable formatting; full `Date` objects can be added later if needed)
**/
// Use `defaultFeatures: false` only if we need to avoid native-tls/openssl in CI.
// For now, keep defaults and tighten once we confirm the feature matrix we want.
@:rustCargo({ name: "mysql", version: "27" })
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
	var handle:Dynamic;

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
		untyped __rust__(
			"{
				let hdyn = {0};
				let h = hdyn.downcast_ref::<std::sync::Arc<std::sync::Mutex<Option<mysql::Conn>>>>()
					.unwrap_or_else(|| hxrt::exception::throw(hxrt::dynamic::from(\"Mysql.close: invalid handle\".to_string())));
				let mut g = h.lock().unwrap();
				let _ = g.take();
			}",
			handle
		);
	}

	public function request(sql:String):ResultSet {
		var res:HxRef<QueryResultHandle> = untyped __rust__(
			"{
				use mysql::prelude::*;
				use mysql::Value;

				let hdyn = {0};
				let h = hdyn.downcast_ref::<std::sync::Arc<std::sync::Mutex<Option<mysql::Conn>>>>()
					.unwrap_or_else(|| hxrt::exception::throw(hxrt::dynamic::from(\"Mysql.request: invalid handle\".to_string())));
				let mut g = h.lock().unwrap();
				let conn = g.as_mut().unwrap_or_else(|| hxrt::exception::throw(hxrt::dynamic::from(\"Mysql.request: connection closed\".to_string())));

				let mut q = conn.query_iter({1}.as_str())
					.unwrap_or_else(|e| hxrt::exception::throw(hxrt::dynamic::from(format!(\"Mysql.request: {e}\"))));

					let cols = q.columns();
					let names_vec: Vec<String> = cols.as_ref().iter().map(|c| c.name_str().to_string()).collect();
					let names = hxrt::array::Array::<String>::from_vec(names_vec);

				let mut rows_out: Vec<hxrt::array::Array<hxrt::dynamic::Dynamic>> = Vec::new();
				for row_res in q.by_ref() {
					let row = row_res.unwrap_or_else(|e| hxrt::exception::throw(hxrt::dynamic::from(format!(\"Mysql.request: {e}\"))));
					let mut vals: Vec<hxrt::dynamic::Dynamic> = Vec::new();
					for v in row.unwrap().into_iter() {
						let d = match v {
							Value::NULL => hxrt::dynamic::Dynamic::null(),
							Value::Int(x) => {
								let y: i32 = (x.clamp(i32::MIN as i64, i32::MAX as i64)) as i32;
								hxrt::dynamic::from(y)
							}
							Value::UInt(x) => {
								let y: i32 = (x.min(i32::MAX as u64)) as i32;
								hxrt::dynamic::from(y)
							}
							Value::Float(x) => hxrt::dynamic::from(x as f64),
							Value::Double(x) => hxrt::dynamic::from(x),
							Value::Bytes(b) => {
								match String::from_utf8(b.clone()) {
									Ok(s) => hxrt::dynamic::from(s),
									Err(_) => {
										let bytes = hxrt::bytes::Bytes::from_vec(b);
										let href = hxrt::cell::HxRc::new(hxrt::cell::HxCell::new(bytes));
										hxrt::dynamic::from(href)
									}
								}
							}
							Value::Date(y, m, d, hh, mm, ss, micros) => {
								let s = format!(\"{y:04}-{m:02}-{d:02} {hh:02}:{mm:02}:{ss:02}.{micros:06}\");
								hxrt::dynamic::from(s)
							}
							Value::Time(neg, days, hh, mm, ss, micros) => {
								let sign = if neg { \"-\" } else { \"\" };
								let s = format!(\"{sign}{days}:{hh:02}:{mm:02}:{ss:02}.{micros:06}\");
								hxrt::dynamic::from(s)
							}
						};
						vals.push(d);
					}
					rows_out.push(hxrt::array::Array::<hxrt::dynamic::Dynamic>::from_vec(vals));
				}

				let rows_arr = hxrt::array::Array::<hxrt::array::Array<hxrt::dynamic::Dynamic>>::from_vec(rows_out);
				hxrt::db::query_result_new(names, rows_arr)
			}",
			handle,
			sql
		);
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

	public function addValue(sb:StringBuf, v:Dynamic):Void {
		var rendered:String = untyped __rust__(
			"{
				let v = {0};
				let out: String = if v.is_null() {
					String::from(\"NULL\")
				} else if let Some(x) = v.downcast_ref::<i32>() {
					x.to_string()
				} else if let Some(x) = v.downcast_ref::<f64>() {
					x.to_string()
				} else if let Some(x) = v.downcast_ref::<bool>() {
					if *x { \"1\".to_string() } else { \"0\".to_string() }
				} else if let Some(b) = v.downcast_ref::<hxrt::cell::HxRef<hxrt::bytes::Bytes>>() {
					// Bytes: x'ABCD...'
					let data = b.borrow();
					let slice = data.as_slice();
					let mut s = String::with_capacity(2 + slice.len() * 2 + 1);
					s.push_str(\"x'\");
					const HEX: &[u8; 16] = b\"0123456789ABCDEF\";
					for byte in slice {
						s.push(HEX[(byte >> 4) as usize] as char);
						s.push(HEX[(byte & 0xF) as usize] as char);
					}
					s.push_str(\"'\");
					s
				} else {
					// Strings (and everything else): quote + MySQL-ish escaping.
					let s = if let Some(s) = v.downcast_ref::<String>() { s.clone() } else { v.to_haxe_string() };
					let escaped = s.replace(\"\\\\\", \"\\\\\\\\\").replace(\"'\", \"\\\\'\");
					format!(\"'{}'\", escaped)
				};
				out
			}",
			v
		);
		sb.add(rendered);
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

	public function next():Dynamic {
		return NativeQueryResult.nextRowObject(res);
	}

	public function results():List<Dynamic> {
		var l: List<Dynamic> = new List<Dynamic>();
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
