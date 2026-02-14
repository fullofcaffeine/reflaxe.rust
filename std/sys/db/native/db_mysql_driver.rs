use hxrt::cell::HxRef;
use hxrt::db::QueryResult;
use hxrt::dynamic::Dynamic;
use hxrt::exception;
use hxrt::string::HxString;
use mysql::prelude::*;
use mysql::Value;
use std::sync::Mutex;

#[derive(Debug)]
pub struct MysqlConnectionHandle {
    conn: Mutex<Option<mysql::Conn>>,
}

fn throw_db(msg: String) -> ! {
    exception::throw(Dynamic::from(msg))
}

pub fn open_handle(
    host: impl Into<HxString>,
    user: impl Into<HxString>,
    pass: impl Into<HxString>,
    port: i32,
    socket: impl Into<HxString>,
    database: impl Into<HxString>,
) -> HxRef<MysqlConnectionHandle> {
    let host: HxString = host.into();
    let user: HxString = user.into();
    let pass: HxString = pass.into();
    let socket: HxString = socket.into();
    let db_name: HxString = database.into();

    let mut opts = mysql::OptsBuilder::new()
        .ip_or_hostname(Some(host.as_str()))
        .user(Some(user.as_str()))
        .pass(Some(pass.as_str()))
        .tcp_port(port as u16);

    if let Some(s) = socket.as_deref() {
        opts = opts.socket(Some(s));
    }
    if let Some(db) = db_name.as_deref() {
        opts = opts.db_name(Some(db));
    }

    let conn =
        mysql::Conn::new(opts).unwrap_or_else(|e| throw_db(format!("Mysql.connect: {e}")));

    HxRef::new(MysqlConnectionHandle {
        conn: Mutex::new(Some(conn)),
    })
}

pub fn close_handle(handle: &HxRef<MysqlConnectionHandle>) {
    let binding = handle.borrow();
    let mut conn_guard = binding.conn.lock().unwrap_or_else(|e| e.into_inner());
    let _ = conn_guard.take();
}

pub fn request(handle: &HxRef<MysqlConnectionHandle>, sql: &str) -> HxRef<QueryResult> {
    let binding = handle.borrow();
    let mut conn_guard = binding.conn.lock().unwrap_or_else(|e| e.into_inner());
    let conn = conn_guard
        .as_mut()
        .unwrap_or_else(|| throw_db(String::from("Mysql.request: connection closed")));

    let mut q = conn
        .query_iter(sql)
        .unwrap_or_else(|e| throw_db(format!("Mysql.request: {e}")));

    let cols = q.columns();
    let names_vec: Vec<String> = cols
        .as_ref()
        .iter()
        .map(|c| c.name_str().to_string())
        .collect();
    let names = hxrt::array::Array::<String>::from_vec(names_vec);

    let mut rows_out: Vec<hxrt::array::Array<hxrt::dynamic::Dynamic>> = Vec::new();
    for row_res in q.by_ref() {
        let row =
            row_res.unwrap_or_else(|e| throw_db(format!("Mysql.request: {e}")));
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
                Value::Bytes(b) => match String::from_utf8(b.clone()) {
                    Ok(s) => hxrt::dynamic::from(s),
                    Err(_) => {
                        let bytes = hxrt::bytes::Bytes::from_vec(b);
                        hxrt::dynamic::from(HxRef::new(bytes))
                    }
                },
                Value::Date(y, m, d, hh, mm, ss, micros) => {
                    let s =
                        format!("{y:04}-{m:02}-{d:02} {hh:02}:{mm:02}:{ss:02}.{micros:06}");
                    hxrt::dynamic::from(s)
                }
                Value::Time(neg, days, hh, mm, ss, micros) => {
                    let sign = if neg { "-" } else { "" };
                    let s = format!("{sign}{days}:{hh:02}:{mm:02}:{ss:02}.{micros:06}");
                    hxrt::dynamic::from(s)
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
    let escaped = raw.replace('\\', "\\\\").replace('\'', "\\'");
    format!("'{escaped}'")
}
