pub fn directory(path: &str) -> String {
    match path.rfind(['/', '\\']) {
        Some(index) => path[..index].to_string(),
        None => String::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::directory;

    #[test]
    fn directory_matches_haxe_separator_edges() {
        assert_eq!(directory("alpha/beta/gamma.txt"), "alpha/beta");
        assert_eq!(directory("single.txt"), "");
        assert_eq!(directory("/root/file.txt"), "/root");
        assert_eq!(directory("alpha/beta/"), "alpha/beta");
        assert_eq!(directory(""), "");
        assert_eq!(directory("/"), "");
        assert_eq!(directory(r"C:\foo\bar.txt"), r"C:\foo");
        assert_eq!(directory("C:/foo/bar.txt"), "C:/foo");
        assert_eq!(directory(r"alpha\beta\file.txt"), r"alpha\beta");
    }
}
