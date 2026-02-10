package sys.db;

import hxrt.db.QueryResultHandle;
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
	- The connection is stored as a `Dynamic` handle containing:
	  `Arc<Mutex<Option<rusqlite::Connection>>>`, so `close()` can drop it safely.
	- Queries are executed synchronously and results are materialized into
	  `hxrt::db::QueryResult` for cursor-style access.
**/
@:rustCargo({ name: "rusqlite", version: "0.38", features: ["bundled"] })
@:coreApi
class Sqlite {
	public static function open(file:String):Connection {
		return new SqliteConnection(file);
	}
}

private class SqliteConnection implements Connection {
	var handle: Dynamic;

	public function new(file:String) {
		handle = untyped __rust__(
			"{
				let conn = rusqlite::Connection::open({0}.as_str())
					.unwrap_or_else(|e| hxrt::exception::throw(hxrt::dynamic::from(format!(\"Sqlite.open: {e}\"))));
				hxrt::dynamic::from(std::sync::Arc::new(std::sync::Mutex::new(Some(conn))))
			}",
			file
		);
	}

	public function close():Void {
		untyped __rust__(
			"{
				let hdyn = {0};
				let h = hdyn.downcast_ref::<std::sync::Arc<std::sync::Mutex<Option<rusqlite::Connection>>>>()
					.unwrap_or_else(|| hxrt::exception::throw(hxrt::dynamic::from(\"Sqlite.close: invalid handle\".to_string())));
				let mut g = h.lock().unwrap();
				let _ = g.take();
			}",
			handle
		);
	}

	public function request(sql:String):ResultSet {
		var res: HxRef<QueryResultHandle> = untyped __rust__(
			"{
				use rusqlite::types::ValueRef;

				let hdyn = {0};
				let h = hdyn.downcast_ref::<std::sync::Arc<std::sync::Mutex<Option<rusqlite::Connection>>>>()
					.unwrap_or_else(|| hxrt::exception::throw(hxrt::dynamic::from(\"Sqlite.request: invalid handle\".to_string())));
				let mut g = h.lock().unwrap();
				let conn = g.as_mut().unwrap_or_else(|| hxrt::exception::throw(hxrt::dynamic::from(\"Sqlite.request: connection closed\".to_string())));

				let mut stmt = conn.prepare({1}.as_str())
					.unwrap_or_else(|e| hxrt::exception::throw(hxrt::dynamic::from(format!(\"Sqlite.request: {e}\"))));

				let names_vec: Vec<String> = stmt.column_names().into_iter().map(|s| s.to_string()).collect();
				let names = hxrt::array::Array::<String>::from_vec(names_vec);
				let col_count: usize = stmt.column_count();

				let mut rows_out: Vec<hxrt::array::Array<hxrt::dynamic::Dynamic>> = Vec::new();
				let mut rows = stmt.query([])
					.unwrap_or_else(|e| hxrt::exception::throw(hxrt::dynamic::from(format!(\"Sqlite.request: {e}\"))));

				while let Some(row) = rows.next()
					.unwrap_or_else(|e| hxrt::exception::throw(hxrt::dynamic::from(format!(\"Sqlite.request: {e}\")))) {
					let mut vals: Vec<hxrt::dynamic::Dynamic> = Vec::new();
					for i in 0..col_count {
						let v = row.get_ref(i)
							.unwrap_or_else(|e| hxrt::exception::throw(hxrt::dynamic::from(format!(\"Sqlite.request: {e}\"))));
						let d = match v {
							ValueRef::Null => hxrt::dynamic::Dynamic::null(),
							ValueRef::Integer(x) => {
								let y: i32 = (x.clamp(i32::MIN as i64, i32::MAX as i64)) as i32;
								hxrt::dynamic::from(y)
							}
							ValueRef::Real(x) => hxrt::dynamic::from(x),
							ValueRef::Text(b) => hxrt::dynamic::from(String::from_utf8_lossy(b).to_string()),
							ValueRef::Blob(b) => {
								let bytes = hxrt::bytes::Bytes::from_vec(b.to_vec());
								let href = hxrt::cell::HxRc::new(hxrt::cell::HxCell::new(bytes));
								hxrt::dynamic::from(href)
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
					// Strings (and everything else): quote + escape single quotes by doubling.
					let s = if let Some(s) = v.downcast_ref::<String>() { s.clone() } else { v.to_haxe_string() };
					let escaped = s.replace(\"'\", \"''\");
					format!(\"'{}'\", escaped)
				};
				out
			}",
			v
		);
		sb.add(rendered);
	}

	public function lastInsertId():Int {
		return untyped __rust__(
			"{
				let hdyn = {0};
				let h = hdyn.downcast_ref::<std::sync::Arc<std::sync::Mutex<Option<rusqlite::Connection>>>>()
					.unwrap_or_else(|| hxrt::exception::throw(hxrt::dynamic::from(\"Sqlite.lastInsertId: invalid handle\".to_string())));
				let mut g = h.lock().unwrap();
				let conn = g.as_mut().unwrap_or_else(|| hxrt::exception::throw(hxrt::dynamic::from(\"Sqlite.lastInsertId: connection closed\".to_string())));
				conn.last_insert_rowid() as i32
			}",
			handle
		);
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

	var res: HxRef<QueryResultHandle>;

	public function new(res:HxRef<QueryResultHandle>) {
		this.res = res;
	}

	function get_length():Int {
		return untyped __rust__("hxrt::db::query_result_length(&{0})", res);
	}

	function get_nfields():Int {
		return untyped __rust__("hxrt::db::query_result_nfields(&{0})", res);
	}

	public function hasNext():Bool {
		return untyped __rust__("hxrt::db::query_result_has_next(&{0})", res);
	}

	public function next():Dynamic {
		return untyped __rust__("hxrt::db::query_result_next_row_object(&{0})", res);
	}

	public function results():List<Dynamic> {
		var l = new List();
		while (hasNext()) {
			l.add(next());
		}
		return l;
	}

	public function getResult(n:Int):String {
		return untyped __rust__("hxrt::db::query_result_get_result(&{0}, {1})", res, n);
	}

	public function getIntResult(n:Int):Int {
		return untyped __rust__("hxrt::db::query_result_get_int_result(&{0}, {1})", res, n);
	}

	public function getFloatResult(n:Int):Float {
		return untyped __rust__("hxrt::db::query_result_get_float_result(&{0}, {1})", res, n);
	}

	public function getFieldsNames():Null<Array<String>> {
		// The upstream API is nullable; return `null` when there are no fields.
		return untyped __rust__(
			"{
				let n = hxrt::db::query_result_nfields(&{0});
				if n == 0 { hxrt::array::Array::<String>::null() } else { hxrt::db::query_result_fields(&{0}) }
			}",
			res
		);
	}
}
