pub fn open_handle(
    host: impl Into<hxrt::string::HxString>,
    user: impl Into<hxrt::string::HxString>,
    pass: impl Into<hxrt::string::HxString>,
    port: i32,
    socket: impl Into<hxrt::string::HxString>,
    database: impl Into<hxrt::string::HxString>,
) -> hxrt::dynamic::Dynamic {
    let host: hxrt::string::HxString = host.into();
    let user: hxrt::string::HxString = user.into();
    let pass: hxrt::string::HxString = pass.into();
    let socket: hxrt::string::HxString = socket.into();
    let db_name: hxrt::string::HxString = database.into();

    let mut b = mysql::OptsBuilder::new()
        .ip_or_hostname(Some(host.as_str()))
        .user(Some(user.as_str()))
        .pass(Some(pass.as_str()))
        .tcp_port(port as u16);

    if let Some(s) = socket.as_deref() {
        b = b.socket(Some(s));
    }
    if let Some(db) = db_name.as_deref() {
        b = b.db_name(Some(db));
    }

    let conn = mysql::Conn::new(b)
        .unwrap_or_else(|e| hxrt::exception::throw(hxrt::dynamic::from(format!("Mysql.connect: {e}"))));
    hxrt::dynamic::from(std::sync::Arc::new(std::sync::Mutex::new(Some(conn))))
}
