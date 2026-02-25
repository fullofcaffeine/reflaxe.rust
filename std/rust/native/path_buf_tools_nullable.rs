/// `path_buf_tools_nullable` (portable nullable-string profile)
///
/// Typed helper module backing `rust.PathBufTools` when Haxe `String` lowers to
/// `hxrt::string::HxString`.
#[derive(Debug)]
pub struct PathBufTools;

#[allow(non_snake_case)]
impl PathBufTools {
    pub fn fromString(s: hxrt::string::HxString) -> std::path::PathBuf {
        std::path::PathBuf::from(s.as_str())
    }

    pub fn join(
        p: &std::path::PathBuf,
        child: hxrt::string::HxString,
    ) -> std::path::PathBuf {
        p.join(child.as_str())
    }

    pub fn push(
        p: &std::path::PathBuf,
        child: hxrt::string::HxString,
    ) -> std::path::PathBuf {
        let mut out = p.clone();
        out.push(child.as_str());
        out
    }

    pub fn toStringLossy(p: &std::path::PathBuf) -> hxrt::string::HxString {
        hxrt::string::HxString::from(p.as_path().to_string_lossy().to_string())
    }

    pub fn fileName(p: &std::path::PathBuf) -> Option<hxrt::string::HxString> {
        p.file_name()
            .map(|s| hxrt::string::HxString::from(s.to_string_lossy().to_string()))
    }
}
