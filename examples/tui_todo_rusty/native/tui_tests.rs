#[cfg(test)]
mod tests {
    #[test]
    fn renders_expected_after_scripted_actions() {
        let frame = crate::harness::Harness::render_scenario();

        assert!(frame.contains("Todo"));
        assert!(frame.contains("[x] bootstrap reflaxe.rust"));
        assert!(frame.contains(">[x] add enums + switch"));
        assert!(frame.contains(" [x] ship ratatui demo"));
    }
}

