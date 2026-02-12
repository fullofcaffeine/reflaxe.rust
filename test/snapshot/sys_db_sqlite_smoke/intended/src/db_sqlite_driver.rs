pub fn open_handle(file: String) -> hxrt::dynamic::Dynamic {
    let conn = rusqlite::Connection::open(file.as_str()).unwrap_or_else(|e| {
        hxrt::exception::throw(hxrt::dynamic::from(format!("Sqlite.open: {e}")))
    });
    hxrt::dynamic::from(std::sync::Arc::new(std::sync::Mutex::new(Some(conn))))
}
