use hxrt::cell::HxRef;
use hxrt::db::QueryResult;
use hxrt::dynamic::Dynamic;
use hxrt::exception;
use hxrt::string::HxString;
use rusqlite::types::ValueRef;
use std::sync::Mutex;

#[derive(Debug)]
pub struct SqliteConnectionHandle {
    conn: Mutex<Option<rusqlite::Connection>>,
}

fn throw_db(msg: String) -> ! {
    exception::throw(Dynamic::from(msg))
}

pub fn open_handle(file: impl Into<HxString>) -> HxRef<SqliteConnectionHandle> {
    let file: HxString = file.into();
    let conn = rusqlite::Connection::open(file.as_str())
        .unwrap_or_else(|e| throw_db(format!("Sqlite.open: {e}")));

    HxRef::new(SqliteConnectionHandle {
        conn: Mutex::new(Some(conn)),
    })
}

pub fn close_handle(handle: &HxRef<SqliteConnectionHandle>) {
    let binding = handle.borrow();
    let mut conn_guard = binding.conn.lock().unwrap_or_else(|e| e.into_inner());
    let _ = conn_guard.take();
}

pub fn request(handle: &HxRef<SqliteConnectionHandle>, sql: &str) -> HxRef<QueryResult> {
    let binding = handle.borrow();
    let mut conn_guard = binding.conn.lock().unwrap_or_else(|e| e.into_inner());
    let conn = conn_guard
        .as_mut()
        .unwrap_or_else(|| throw_db(String::from("Sqlite.request: connection closed")));

    let mut stmt = conn
        .prepare(sql)
        .unwrap_or_else(|e| throw_db(format!("Sqlite.request: {e}")));

    let names_vec: Vec<String> = stmt
        .column_names()
        .into_iter()
        .map(|s| s.to_string())
        .collect();
    let names = hxrt::array::Array::<String>::from_vec(names_vec);
    let col_count: usize = stmt.column_count();

    let mut rows_out: Vec<hxrt::array::Array<hxrt::dynamic::Dynamic>> = Vec::new();
    let mut rows = stmt
        .query([])
        .unwrap_or_else(|e| throw_db(format!("Sqlite.request: {e}")));

    while let Some(row) = rows
        .next()
        .unwrap_or_else(|e| throw_db(format!("Sqlite.request: {e}")))
    {
        let mut vals: Vec<hxrt::dynamic::Dynamic> = Vec::new();
        for i in 0..col_count {
            let v = row
                .get_ref(i)
                .unwrap_or_else(|e| throw_db(format!("Sqlite.request: {e}")));
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
                    hxrt::dynamic::from(HxRef::new(bytes))
                }
            };
            vals.push(d);
        }
        rows_out.push(hxrt::array::Array::<hxrt::dynamic::Dynamic>::from_vec(vals));
    }

    let rows_arr =
        hxrt::array::Array::<hxrt::array::Array<hxrt::dynamic::Dynamic>>::from_vec(rows_out);
    hxrt::db::query_result_new(names, rows_arr)
}

pub fn last_insert_id(handle: &HxRef<SqliteConnectionHandle>) -> i32 {
    let binding = handle.borrow();
    let mut conn_guard = binding.conn.lock().unwrap_or_else(|e| e.into_inner());
    let conn = conn_guard
        .as_mut()
        .unwrap_or_else(|| throw_db(String::from("Sqlite.lastInsertId: connection closed")));
    conn.last_insert_rowid() as i32
}

pub fn render_sql_value(v: Dynamic) -> String {
    if v.is_null() {
        return String::from("NULL");
    }

    if let Some(x) = v.downcast_ref::<i32>() {
        return x.to_string();
    }
    if let Some(x) = v.downcast_ref::<f64>() {
        return x.to_string();
    }
    if let Some(x) = v.downcast_ref::<bool>() {
        return if *x {
            String::from("1")
        } else {
            String::from("0")
        };
    }
    if let Some(b) = v.downcast_ref::<hxrt::cell::HxRef<hxrt::bytes::Bytes>>() {
        let data = b.borrow();
        let slice = data.as_slice();
        let mut s = String::with_capacity(2 + slice.len() * 2 + 1);
        s.push_str("x'");
        const HEX: &[u8; 16] = b"0123456789ABCDEF";
        for byte in slice {
            s.push(HEX[(byte >> 4) as usize] as char);
            s.push(HEX[(byte & 0xF) as usize] as char);
        }
        s.push('\'');
        return s;
    }

    let raw = if let Some(s) = v.downcast_ref::<String>() {
        s.clone()
    } else if let Some(s) = v.downcast_ref::<HxString>() {
        s.as_deref().unwrap_or("").to_string()
    } else {
        v.to_haxe_string()
    };
    let escaped = raw.replace('\'', "''");
    format!("'{escaped}'")
}
