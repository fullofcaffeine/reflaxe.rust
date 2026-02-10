#[cfg(test)]
mod tests {
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
        let frame = crate::harness::Harness::render_scenario_palette();
        let got = normalize_frame(&frame);
        assert_eq!(got.lines().count(), 24);

        let expected = r#" Dashboard | Tasks | Help
┌Tasks─────────────────────────────────────────────────────────────────────────┐
│[x] [inbox] bootstrap reflaxe.rust                                            │
│[ ] [inbox] ship crazy TUI harness                                            │
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
}
