fn main() {
    print!(
        "{}",
        std::env::var("M47_NATIVE_COMMAND_ENV").unwrap_or_default()
    );
}
