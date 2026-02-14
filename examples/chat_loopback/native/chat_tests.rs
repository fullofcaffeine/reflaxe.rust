#[cfg(test)]
mod tests {
    use std::sync::{Mutex, OnceLock};

    fn harness_lock() -> &'static Mutex<()> {
        static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
        LOCK.get_or_init(|| Mutex::new(()))
    }

    #[test]
    fn transcript_shape_and_profile_marker() {
        let _guard = harness_lock().lock().unwrap_or_else(|e| e.into_inner());
        assert!(crate::harness::Harness::transcript_has_expected_shape());

        let profile = crate::harness::Harness::profile_name();
        let transcript = crate::harness::Harness::run_transcript();
        let lines: Vec<&str> = transcript.lines().collect();

        assert_eq!(lines.len(), 4);
        assert!(lines[3].starts_with("BYE|"));
        assert!(lines[3].contains(profile.as_str()));
    }

    #[test]
    fn parser_and_codec_contracts() {
        let _guard = harness_lock().lock().unwrap_or_else(|e| e.into_inner());
        assert!(crate::harness::Harness::parser_rejects_invalid_command());
        assert!(crate::harness::Harness::codec_roundtrip_works());
    }

    #[test]
    fn profile_is_one_of_supported_variants() {
        let _guard = harness_lock().lock().unwrap_or_else(|e| e.into_inner());
        let profile = crate::harness::Harness::profile_name();
        assert!(
            ["portable", "idiomatic", "rusty", "metal"].contains(&profile.as_str()),
            "unexpected profile: {profile}"
        );
    }
}
