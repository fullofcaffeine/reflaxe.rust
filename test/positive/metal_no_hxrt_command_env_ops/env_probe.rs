fn main() {
    let mode = std::env::args().nth(1).unwrap_or_default();

    if mode == "clear" {
        let path = if std::env::var_os("PATH").is_some() {
            "present"
        } else {
            "missing"
        };
        print!(
            "path={};keep={}",
            path,
            std::env::var("M48_KEEP_ME").unwrap_or_default()
        );
        return;
    }

    print!(
        "removed={};keep={}",
        std::env::var("M48_REMOVE_ME").unwrap_or_default(),
        std::env::var("M48_KEEP_ME").unwrap_or_default()
    );
}
