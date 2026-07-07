/// `native_file_tools`
///
/// Typed helper module backing `rust.fs.NativeFiles`.
///
/// This module intentionally uses direct `std::fs` APIs and `Result<_, String>` so the metal
/// no-hxrt fixture can prove Rust-native file/path operations without depending on portable
/// `sys.io.File` runtime handles.
#[derive(Debug)]
pub struct NativeFiles;

#[allow(non_snake_case)]
impl NativeFiles {
    pub fn writeString(path: &std::path::PathBuf, content: String) -> Result<bool, String> {
        std::fs::write(path, content.as_bytes())
            .map(|_| true)
            .map_err(|err| err.to_string())
    }

    pub fn readString(path: &std::path::PathBuf) -> Result<String, String> {
        std::fs::read_to_string(path).map_err(|err| err.to_string())
    }

    pub fn exists(path: &std::path::PathBuf) -> bool {
        path.exists()
    }

    pub fn removeFile(path: &std::path::PathBuf) -> Result<bool, String> {
        std::fs::remove_file(path)
            .map(|_| true)
            .map_err(|err| err.to_string())
    }
}
