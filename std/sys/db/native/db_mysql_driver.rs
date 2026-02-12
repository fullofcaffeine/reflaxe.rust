pub fn open_handle(
    host: String,
    user: String,
    pass: String,
    port: i32,
    socket: Option<String>,
    database: Option<String>,
) -> hxrt::dynamic::Dynamic {
    let socket = socket;
    let db_name = database;
    let mut b = mysql::OptsBuilder::new()
        .ip_or_hostname(Some(host.as_str()))
        .user(Some(user.as_str()))
        .pass(Some(pass.as_str()))
        .tcp_port(port as u16);

    if let Some(s) = socket.as_ref() {
        b = b.socket(Some(s.as_str()));
    }
    if let Some(db) = db_name.as_ref() {
        b = b.db_name(Some(db.as_str()));
    }

    let conn = mysql::Conn::new(b)
        .unwrap_or_else(|e| hxrt::exception::throw(hxrt::dynamic::from(format!("Mysql.connect: {e}"))));
    hxrt::dynamic::from(std::sync::Arc::new(std::sync::Mutex::new(Some(conn))))
}
