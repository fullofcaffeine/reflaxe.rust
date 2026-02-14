#[cfg(test)]
mod tests {
    use std::sync::{Mutex, OnceLock};

    fn harness_lock() -> &'static Mutex<()> {
        static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
        LOCK.get_or_init(|| Mutex::new(()))
    }

    fn normalize_frame(s: &str) -> String {
        let trimmed = s.trim_end_matches(&['\r', '\n'][..]);
        trimmed
            .lines()
            .map(|l| l.trim_end())
            .collect::<Vec<_>>()
            .join("\n")
    }

    #[test]
    fn scenario_tasks_renders() {
        let _guard = harness_lock().lock().unwrap_or_else(|e| e.into_inner());
        let frame = crate::harness::Harness::render_scenario_tasks();
        let got = normalize_frame(&frame);
        assert_eq!(got.lines().count(), 24);

        let expected = r#" Dashboard | Tasks | Help
┌Task Details──────────────────────────────────────────────────────────────────┐
│Title: reach v1.0 stdlib parity                                               │
│Project: inbox                                                                │
│Tags: -                                                                       │
│Done: no                                                                      │
│                                                                              │
│Notes:                                                                        │
│(none)                                                                        │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
[-] details | 2/4*"#;
        assert_eq!(got, expected);
    }

    #[test]
    fn scenario_palette_renders() {
        let _guard = harness_lock().lock().unwrap_or_else(|e| e.into_inner());
        let frame = crate::harness::Harness::render_scenario_palette();
        let got = normalize_frame(&frame);
        assert_eq!(got.lines().count(), 24);

        let expected = r#" Dashboard | Tasks | Help
┌Tasks─────────────────────────────────────────────────────────────────────────┐
│[x] [inbox] bootstrap reflaxe.rust                                            │
│[ ] [inbox] ship TUI harness                                                  │
│[ ] [inbox] reach v1.0 stdlib parity                                          │
│[ ] [in┌Command Palette───────────────────────────────────────────────┐       │
│       │> go:                                                         │       │
│       │                                                              │       │
│       │> Go: Help                                                    │       │
│       │  Go: Tasks                                                   │       │
│       │  Go: Dashboard                                               │       │
│       │                                                              │       │
│       │                                                              │       │
│       │                                                              │       │
│       │                                                              │       │
│       │                                                              │       │
│       │                                                              │       │
│       │                                                              │       │
│       └──────────────────────────────────────────────────────────────┘       │
│                                                                              │
│                                                                              │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
[/] tasks | 1/4"#;
        assert_eq!(got, expected);
    }

    #[test]
    fn scenario_edit_title_renders() {
        let _guard = harness_lock().lock().unwrap_or_else(|e| e.into_inner());
        let frame = crate::harness::Harness::render_scenario_edit_title();
        let got = normalize_frame(&frame);
        assert_eq!(got.lines().count(), 24);

        let expected = r#" Dashboard | Tasks | Help
┌Task Details──────────────────────────────────────────────────────────────────┐
│Title: bootstrap reflaxe.rustX!                                               │
│Project: inbox                                                                │
│Tags: -                                                                       │
│Done: yes                                                                     │
│                                                                              │
│Notes:                                                                        │
│(none)                                                                        │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
[/] details | 1/4* | updated"#;
        assert_eq!(got, expected);
    }

    #[test]
    fn scenario_dashboard_fx_deterministic() {
        let _guard = harness_lock().lock().unwrap_or_else(|e| e.into_inner());
        let a = normalize_frame(&crate::harness::Harness::render_scenario_dashboard_fx());
        let b = normalize_frame(&crate::harness::Harness::render_scenario_dashboard_fx());
        assert_eq!(a, b);
        assert!(a.contains("Hyperfocus"));
        assert!(a.to_lowercase().contains("mode: pulse"));
        assert!(a.contains("Pulse:"));
        assert!(a.contains("Flow: ["));
    }

    #[test]
    fn persistence_roundtrip() {
        let _guard = harness_lock().lock().unwrap_or_else(|e| e.into_inner());
        assert!(crate::harness::Harness::persistence_roundtrip());
    }

    #[test]
    fn persistence_migrates_v0() {
        let _guard = harness_lock().lock().unwrap_or_else(|e| e.into_inner());
        assert!(crate::harness::Harness::persistence_migrates_v0());
    }

    #[test]
    fn persistence_autosave_debounce() {
        let _guard = harness_lock().lock().unwrap_or_else(|e| e.into_inner());
        assert!(crate::harness::Harness::persistence_autosave_debounce());
    }

    #[test]
    fn persistence_rejects_invalid_schema() {
        let _guard = harness_lock().lock().unwrap_or_else(|e| e.into_inner());
        assert!(crate::harness::Harness::persistence_rejects_invalid_schema());
    }
}
