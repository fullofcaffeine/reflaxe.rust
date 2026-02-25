/// `path_buf_tools` (non-nullable string profile)
///
/// Typed helper module backing `rust.PathBufTools` when Haxe `String` lowers to owned
/// Rust `String`.
#[derive(Debug)]
pub struct PathBufTools;

#[allow(non_snake_case)]
impl PathBufTools {
    pub fn fromString(s: String) -> std::path::PathBuf {
        std::path::PathBuf::from(s)
    }

    pub fn join(p: &std::path::PathBuf, child: String) -> std::path::PathBuf {
        p.join(child.as_str())
    }

    pub fn push(p: &std::path::PathBuf, child: String) -> std::path::PathBuf {
        let mut out = p.clone();
        out.push(child.as_str());
        out
    }

    pub fn toStringLossy(p: &std::path::PathBuf) -> String {
        p.as_path().to_string_lossy().to_string()
    }

    pub fn fileName(p: &std::path::PathBuf) -> Option<String> {
        p.file_name().map(|s| s.to_string_lossy().to_string())
    }
}
