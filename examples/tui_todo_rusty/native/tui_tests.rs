#[cfg(test)]
mod tests {
    const EXPECTED_FRAME: &str = "┌Todo──────────────────────────────────────────────────────┐\n\
│ [x] bootstrap reflaxe.rust                               │\n\
│>[x] add enums + switch                                   │\n\
│ [x] ship ratatui demo                                    │\n\
│                                                          │\n\
│                                                          │\n\
│                                                          │\n\
│                                                          │\n\
│                                                          │\n\
└──────────────────────────────────────────────────────────┘\n";

    #[test]
    fn renders_expected_after_scripted_actions() {
        let frame = crate::harness::Harness::render_scenario();

        assert_eq!(frame, EXPECTED_FRAME);
    }
}
