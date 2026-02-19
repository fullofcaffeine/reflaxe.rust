use crossterm::event::{self, Event, KeyCode};
use crossterm::terminal::{
    disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen,
};
use crossterm::ExecutableCommand;
use ratatui::backend::{CrosstermBackend, TestBackend};
use ratatui::prelude::*;
use ratatui::widgets::*;
use std::cell::{Cell, RefCell};
use std::f32::consts::PI;
use std::io::{self, IsTerminal, Stdout, Write};
use std::time::Duration;

thread_local! {
    static TERMINAL: RefCell<Option<Terminal<CrosstermBackend<Stdout>>>> = RefCell::new(None);
    static HEADLESS: Cell<bool> = Cell::new(false);
    static HEADLESS_SET: Cell<bool> = Cell::new(false);
}

// High-level events and key codes are defined in Haxe under `std/rust/tui/*` and compiled to Rust
// modules named `rust_tui_*`.
use crate::rust_tui_constraint::Constraint as HxConstraint;
use crate::rust_tui_event::Event as HxEvent;
use crate::rust_tui_fx_kind::FxKind as HxFxKind;
use crate::rust_tui_key_code::KeyCode as HxKeyCode;
use crate::rust_tui_layout_dir::LayoutDir as HxLayoutDir;
use crate::rust_tui_style_token::StyleToken as HxStyleToken;
use crate::rust_tui_ui_node::UiNode as HxUiNode;

fn transform_fx_line(line: &str, effect: &HxFxKind, phase: i32, width: usize) -> String {
    const GLITCH_CHARS: [char; 8] = ['#', '@', '%', '*', '+', '~', '!', '?'];

    match effect {
        HxFxKind::None => line.to_string(),
        HxFxKind::Typewriter => {
            let chars: Vec<char> = line.chars().collect();
            if chars.is_empty() {
                return String::new();
            }
            let reveal = (phase.max(0) as usize) % (chars.len() + 1);
            chars.into_iter().take(reveal).collect()
        }
        HxFxKind::Pulse => line
            .chars()
            .enumerate()
            .flat_map(|(idx, ch)| {
                if !ch.is_ascii_alphabetic() {
                    return vec![ch];
                }
                let pulse_phase = (phase / 2).rem_euclid(4);
                if ((idx as i32 + pulse_phase) % 2) == 0 {
                    vec![ch.to_ascii_uppercase()]
                } else {
                    vec![ch.to_ascii_lowercase()]
                }
            })
            .collect(),
        HxFxKind::Glitch => line
            .chars()
            .enumerate()
            .map(|(idx, ch)| {
                if ch.is_whitespace() {
                    return ch;
                }
                let gate = (phase + (idx as i32 * 3)).rem_euclid(23);
                if gate == 0 || gate == 11 {
                    GLITCH_CHARS[(phase.rem_euclid(GLITCH_CHARS.len() as i32) as usize + idx)
                        % GLITCH_CHARS.len()]
                } else {
                    ch
                }
            })
            .collect(),
        HxFxKind::Marquee => {
            if width == 0 {
                return String::new();
            }
            let chars: Vec<char> = line.chars().collect();
            if chars.is_empty() {
                return String::new();
            }

            let pad = width.max(4);
            let mut track: Vec<char> = Vec::with_capacity(chars.len() + (pad * 2));
            track.extend(std::iter::repeat(' ').take(pad));
            track.extend(chars.iter().copied());
            track.extend(std::iter::repeat(' ').take(pad));

            let len = track.len();
            if len == 0 {
                return String::new();
            }

            let start = phase.rem_euclid(len as i32) as usize;
            (0..width)
                .map(|offset| {
                    let idx = (start + offset) % len;
                    track[idx]
                })
                .collect()
        }
        HxFxKind::ParticleBurst => line.to_string(),
    }
}

fn transform_fx_text(text: &str, effect: &HxFxKind, phase: i32, width: usize) -> String {
    let mut out: Vec<String> = Vec::new();
    let mut has_lines = false;

    for (line_idx, line) in text.lines().enumerate() {
        has_lines = true;
        out.push(transform_fx_line(
            line,
            effect,
            phase + line_idx as i32,
            width,
        ));
    }

    if !has_lines {
        return transform_fx_line(text, effect, phase, width);
    }

    out.join("\n")
}

fn particle_burst_palette() -> [Color; 6] {
    [
        Color::Rgb(255, 110, 148),
        Color::Rgb(255, 172, 87),
        Color::Rgb(255, 225, 102),
        Color::Rgb(114, 214, 166),
        Color::Rgb(112, 188, 255),
        Color::Rgb(194, 152, 255),
    ]
}

fn hash_u32(mut value: u32) -> u32 {
    value ^= value >> 16;
    value = value.wrapping_mul(0x7feb_352d);
    value ^= value >> 15;
    value = value.wrapping_mul(0x846c_a68b);
    value ^ (value >> 16)
}

fn set_particle_cell(
    chars: &mut [Vec<char>],
    colors: &mut [Vec<Option<Color>>],
    x: i32,
    y: i32,
    ch: char,
    color: Color,
) {
    if x < 0 || y < 0 {
        return;
    }
    let ux = x as usize;
    let uy = y as usize;
    if uy >= chars.len() || ux >= chars[uy].len() {
        return;
    }
    chars[uy][ux] = ch;
    colors[uy][ux] = Some(color);
}

fn write_center_text(
    chars: &mut [Vec<char>],
    colors: &mut [Vec<Option<Color>>],
    text: &str,
    center_y: i32,
    color: Color,
) {
    if text.is_empty() || chars.is_empty() {
        return;
    }
    let width = chars[0].len() as i32;
    let y = center_y.clamp(0, chars.len() as i32 - 1);
    let text_len = text.chars().count() as i32;
    let start_x = ((width - text_len) / 2).max(0);
    for (idx, ch) in text.chars().enumerate() {
        set_particle_cell(chars, colors, start_x + idx as i32, y, ch, color);
    }
}

fn particle_burst_lines(text: &str, phase: i32, width: usize, height: usize) -> Vec<Line<'static>> {
    if width == 0 || height == 0 {
        return Vec::new();
    }

    let mut chars = vec![vec![' '; width]; height];
    let mut colors = vec![vec![None; width]; height];
    let palette = particle_burst_palette();
    let ascii_glyphs: [char; 10] = ['*', '+', 'x', 'o', '.', '@', '%', ':', '^', '~'];

    let cx = (width as f32 - 1.0) * 0.5;
    let cy = (height as f32 - 1.0) * 0.5;
    let safe_phase = phase.max(0);
    let phase_f = safe_phase as f32;
    let phase_u = safe_phase as usize;
    let cycle = 68.0;
    let cycle_phase = phase_f % cycle;
    let count = ((width * height) / 11).clamp(72, 360);
    let max_age = 30.0;
    let gravity = 0.036;

    for i in 0..count {
        let seed = hash_u32((i as u32).wrapping_mul(97_531) ^ 0x9e37_79b9);
        let launch_offset = (seed % 24) as f32;
        let mut age = cycle_phase - launch_offset;
        if age < 0.0 {
            age += cycle;
        }
        if age > max_age {
            continue;
        }

        let age_norm = age / max_age;
        let angle_seed = hash_u32(seed ^ (safe_phase as u32).wrapping_mul(31_337));
        let angle = (((angle_seed % 3600) as f32) / 10.0) * (PI / 180.0);
        let speed = 0.70 + (((seed >> 7) % 170) as f32 / 170.0) * 1.35;
        let radial = age * speed;
        let swirl = ((phase_f * 0.09) + i as f32 * 0.37).sin() * (1.0 - age_norm) * 0.95;
        let drift = ((phase_f * 0.07) + i as f32 * 0.21).cos() * 0.42;

        let x = cx + angle.cos() * radial + swirl;
        let y = cy + angle.sin() * radial * 0.58 + age * age * gravity + drift;

        let color_shift = (phase_u / 3) % palette.len();
        let color = palette[(((seed >> 16) as usize) + color_shift) % palette.len()];
        let glyph = ascii_glyphs[((seed >> 22) as usize + (phase_u / 2)) % ascii_glyphs.len()];
        set_particle_cell(
            &mut chars,
            &mut colors,
            x.round() as i32,
            y.round() as i32,
            glyph,
            color,
        );

        // Draw a short path towards the center so particles clearly read as "thrown from center".
        let trail_segments = if age < 8.0 { 3 } else { 2 };
        for seg in 1..=trail_segments {
            let back = seg as f32 / (trail_segments as f32 + 1.0);
            let tx = x + (cx - x) * back;
            let ty = y + (cy - y) * back;
            let trail_char = if seg == trail_segments { '.' } else { ':' };
            let trail_color = palette[((seed >> (8 + seg)) as usize + color_shift) % palette.len()];
            set_particle_cell(
                &mut chars,
                &mut colors,
                tx.round() as i32,
                ty.round() as i32,
                trail_char,
                trail_color,
            );
        }
    }

    // Flashing center core keeps the burst origin visually obvious during the whole celebration.
    let core_color = palette[(phase_u / 2) % palette.len()];
    set_particle_cell(
        &mut chars,
        &mut colors,
        cx.round() as i32,
        cy.round() as i32,
        '*',
        core_color,
    );
    set_particle_cell(
        &mut chars,
        &mut colors,
        cx.round() as i32 - 1,
        cy.round() as i32,
        '+',
        core_color,
    );
    set_particle_cell(
        &mut chars,
        &mut colors,
        cx.round() as i32 + 1,
        cy.round() as i32,
        '+',
        core_color,
    );

    let mut lines = text.lines().filter(|line| !line.trim().is_empty());
    let title = lines.next().unwrap_or("MOMENTUM 100").trim().to_uppercase();
    let subtitle = lines.next().unwrap_or("").trim().to_string();
    write_center_text(
        &mut chars,
        &mut colors,
        &title,
        cy.round() as i32,
        Color::Rgb(245, 245, 250),
    );
    if !subtitle.is_empty() {
        write_center_text(
            &mut chars,
            &mut colors,
            &subtitle,
            cy.round() as i32 + 1,
            Color::Rgb(196, 207, 227),
        );
    }

    let mut out: Vec<Line<'static>> = Vec::with_capacity(height);
    for y in 0..height {
        let mut spans: Vec<Span<'static>> = Vec::with_capacity(width);
        for x in 0..width {
            let ch = chars[y][x].to_string();
            if let Some(color) = colors[y][x] {
                spans.push(Span::styled(
                    ch,
                    Style::default().fg(color).add_modifier(Modifier::BOLD),
                ));
            } else {
                spans.push(Span::raw(ch));
            }
        }
        out.push(Line::from(spans));
    }
    out
}

fn style_for(token: &HxStyleToken) -> Style {
    match token.clone() {
        HxStyleToken::Normal => Style::default(),
        HxStyleToken::Muted => Style::default().fg(Color::Rgb(138, 152, 173)),
        HxStyleToken::Title => Style::default()
            .fg(Color::Rgb(224, 232, 243))
            .add_modifier(Modifier::BOLD),
        HxStyleToken::Accent => Style::default()
            .fg(Color::Rgb(122, 172, 214))
            .add_modifier(Modifier::BOLD),
        HxStyleToken::Selected => Style::default()
            .fg(Color::Rgb(228, 236, 246))
            .bg(Color::Rgb(53, 72, 96))
            .add_modifier(Modifier::BOLD),
        HxStyleToken::Success => Style::default()
            .fg(Color::Rgb(126, 196, 154))
            .add_modifier(Modifier::BOLD),
        HxStyleToken::Warning => Style::default()
            .fg(Color::Rgb(214, 175, 112))
            .add_modifier(Modifier::BOLD),
        HxStyleToken::Danger => Style::default()
            .fg(Color::Rgb(209, 112, 122))
            .add_modifier(Modifier::BOLD),
    }
}

fn constraint_for(c: &HxConstraint) -> ratatui::layout::Constraint {
    match c.clone() {
        HxConstraint::Fixed(cells) => ratatui::layout::Constraint::Length(cells.max(0) as u16),
        HxConstraint::Percent(p) => ratatui::layout::Constraint::Percentage(p.clamp(0, 100) as u16),
        HxConstraint::Min(cells) => ratatui::layout::Constraint::Min(cells.max(0) as u16),
        HxConstraint::Max(cells) => ratatui::layout::Constraint::Max(cells.max(0) as u16),
        HxConstraint::Fill => ratatui::layout::Constraint::Min(0),
    }
}

fn centered_rect(w_percent: i32, h_percent: i32, area: Rect) -> Rect {
    let w = w_percent.clamp(10, 100) as u16;
    let h = h_percent.clamp(10, 100) as u16;

    let vertical = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            ratatui::layout::Constraint::Percentage(((100 - h) / 2) as u16),
            ratatui::layout::Constraint::Percentage(h),
            ratatui::layout::Constraint::Percentage(((100 - h) / 2) as u16),
        ])
        .split(area);

    let horizontal = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            ratatui::layout::Constraint::Percentage(((100 - w) / 2) as u16),
            ratatui::layout::Constraint::Percentage(w),
            ratatui::layout::Constraint::Percentage(((100 - w) / 2) as u16),
        ])
        .split(vertical[1]);

    horizontal[1]
}

fn render_children(frame: &mut Frame, area: Rect, children: &hxrt::array::Array<HxUiNode>) {
    for child in children.iter() {
        render_node(frame, area, &child);
    }
}

fn render_node(frame: &mut Frame, area: Rect, node: &HxUiNode) {
    match node {
        HxUiNode::Empty => {}

        HxUiNode::Layout(dir, constraints, children) => {
            let direction = match dir {
                HxLayoutDir::Horizontal => Direction::Horizontal,
                HxLayoutDir::Vertical => Direction::Vertical,
            };

            let cons: Vec<ratatui::layout::Constraint> =
                constraints.iter().map(|c| constraint_for(&c)).collect();
            let areas = Layout::default()
                .direction(direction)
                .constraints(cons)
                .split(area);

            let mut i: usize = 0;
            for child in children.iter() {
                if i >= areas.len() {
                    break;
                }
                render_node(frame, areas[i], &child);
                i += 1;
            }
        }

        HxUiNode::Overlay(children) => {
            // Draw children over the same rect, in order.
            render_children(frame, area, children);
        }

        HxUiNode::Block(title, children, style) => {
            let block = Block::default()
                .title(title.as_str())
                .borders(Borders::ALL)
                .style(style_for(style));
            let inner = block.inner(area);
            frame.render_widget(block, area);

            render_children(frame, inner, children);
        }

        HxUiNode::Paragraph(text, wrap, style) => {
            let mut p = Paragraph::new(text.as_str()).style(style_for(style));
            if *wrap {
                p = p.wrap(Wrap { trim: false });
            }
            frame.render_widget(p, area);
        }

        HxUiNode::Tabs(titles, selected, style) => {
            let tabs: Vec<Line> = titles
                .iter()
                .map(|t| Line::from(vec![Span::raw(t.as_str().to_string())]))
                .collect();
            let w = Tabs::new(tabs)
                .select((*selected).max(0) as usize)
                .style(style_for(style))
                .highlight_style(style_for(&HxStyleToken::Selected))
                .divider(Span::raw("|"));
            frame.render_widget(w, area);
        }

        HxUiNode::Gauge(title, percent, style) => {
            let p = (*percent).clamp(0, 100) as u16;
            let w = Gauge::default()
                .block(Block::default().title(title.as_str()).borders(Borders::ALL))
                .gauge_style(style_for(style))
                .percent(p);
            frame.render_widget(w, area);
        }

        HxUiNode::List(title, items, selected, style) => {
            let list_items: Vec<ListItem> = items
                .iter()
                .map(|item| ListItem::new(item.as_str().to_string()))
                .collect();
            let list = List::new(list_items)
                .block(Block::default().title(title.as_str()).borders(Borders::ALL))
                .style(style_for(style))
                .highlight_style(style_for(&HxStyleToken::Selected));

            let mut state = ListState::default();
            if *selected >= 0 {
                state.select(Some(*selected as usize));
            }

            frame.render_stateful_widget(list, area, &mut state);
        }

        HxUiNode::Modal(title, body, w_percent, h_percent, style) => {
            let rect = centered_rect(*w_percent, *h_percent, area);
            frame.render_widget(Clear, rect);

            let block = Block::default()
                .title(title.as_str())
                .borders(Borders::ALL)
                .style(style_for(style));
            let inner = block.inner(rect);
            frame.render_widget(block, rect);

            let text = body
                .iter()
                .map(|line| line.as_str().to_string())
                .collect::<Vec<String>>()
                .join("\n");
            let p = Paragraph::new(text)
                .wrap(Wrap { trim: false })
                .style(style_for(&HxStyleToken::Normal));
            frame.render_widget(p, inner);
        }

        HxUiNode::FxText(title, text, effect, phase, style) => {
            let block = Block::default()
                .title(title.as_str())
                .borders(Borders::ALL)
                .style(style_for(style));
            let inner = block.inner(area);
            frame.render_widget(block, area);

            let p = match effect {
                HxFxKind::ParticleBurst => {
                    let lines = particle_burst_lines(
                        text.as_str(),
                        *phase,
                        inner.width as usize,
                        inner.height as usize,
                    );
                    Paragraph::new(lines)
                }
                _ => {
                    let transformed =
                        transform_fx_text(text.as_str(), effect, *phase, inner.width as usize);
                    Paragraph::new(transformed)
                }
            }
            .wrap(Wrap { trim: false })
            .style(style_for(style));
            frame.render_widget(p, inner);
        }
    }
}

// Deterministic renderer for tests/snapshots.
#[allow(dead_code)]
pub fn run_frame(frame: i32, tasks: impl AsRef<str>) {
    println!("--- frame {} ---", frame);
    let rendered = render_headless(tasks.as_ref());
    print!("{}", rendered);
}

// Deterministic renderer for tests/snapshots (no global state, no stdout).
#[allow(dead_code)]
pub fn render_to_string(tasks: impl AsRef<str>) -> String {
    render_headless(tasks.as_ref())
}

pub fn set_headless(headless: bool) {
    HEADLESS.with(|h| h.set(headless));
    HEADLESS_SET.with(|s| s.set(true));
}

pub fn enter() {
    let interactive = io::stdin().is_terminal() && io::stdout().is_terminal();

    let headless = if HEADLESS_SET.with(|s| s.get()) {
        HEADLESS.with(|h| h.get())
    } else {
        !interactive
    };

    HEADLESS.with(|h| h.set(headless));

    if headless {
        return;
    }

    // Even if the Haxe side explicitly requested interactive mode, CI and other non-TTY
    // environments can still call into this. Prefer a clean headless fallback over panicking.
    if !interactive {
        HEADLESS.with(|h| h.set(true));
        return;
    }

    if enable_raw_mode().is_err() {
        HEADLESS.with(|h| h.set(true));
        return;
    }
    let mut stdout = io::stdout();
    if stdout.execute(EnterAlternateScreen).is_err() {
        disable_raw_mode().ok();
        HEADLESS.with(|h| h.set(true));
        return;
    }
    stdout.flush().ok();

    let backend = CrosstermBackend::new(io::stdout());
    match Terminal::new(backend) {
        Ok(terminal) => {
            TERMINAL.with(|t| *t.borrow_mut() = Some(terminal));
        }
        Err(_) => {
            let mut stdout = io::stdout();
            stdout.execute(LeaveAlternateScreen).ok();
            stdout.flush().ok();
            disable_raw_mode().ok();
            HEADLESS.with(|h| h.set(true));
        }
    }
}

pub fn exit() {
    if HEADLESS.with(|h| h.get()) {
        return;
    }

    TERMINAL.with(|t| {
        if let Some(mut term) = t.borrow_mut().take() {
            term.show_cursor().ok();
        }
    });

    let mut stdout = io::stdout();
    stdout.execute(LeaveAlternateScreen).ok();
    stdout.flush().ok();
    disable_raw_mode().ok();
}

pub fn poll_action(timeout_ms: i32) -> i32 {
    if HEADLESS.with(|h| h.get()) {
        // Headless mode is meant for deterministic tests via `render_to_string(...)`.
        // For "real" application loops (like `examples/tui_todo/Main.hx`), if we end up headless
        // (e.g. no TTY), we immediately quit so the program doesn't spin forever.
        return 4;
    }

    let timeout = Duration::from_millis(timeout_ms.max(0) as u64);
    if !event::poll(timeout).unwrap_or(false) {
        return 0;
    }

    match event::read().unwrap() {
        Event::Key(key) => match key.code {
            KeyCode::Up => 1,
            KeyCode::Down => 2,
            KeyCode::Enter | KeyCode::Char(' ') => 3,
            KeyCode::Esc | KeyCode::Char('q') => 4,
            _ => 0,
        },
        _ => 0,
    }
}

pub fn poll_event(timeout_ms: i32) -> HxEvent {
    if HEADLESS.with(|h| h.get()) {
        // Mirror `poll_action`: in headless mode, quit immediately so binaries invoked in CI don't hang.
        return HxEvent::Quit;
    }

    let timeout = Duration::from_millis(timeout_ms.max(0) as u64);
    if !event::poll(timeout).unwrap_or(false) {
        return HxEvent::None;
    }

    match event::read().unwrap() {
        Event::Resize(w, h) => HxEvent::Resize(w as i32, h as i32),
        Event::Key(key) => {
            // Map crossterm modifiers into the Haxe bitmask:
            // 1 = ctrl, 2 = alt, 4 = shift
            let mut mods: i32 = 0;
            if key
                .modifiers
                .contains(crossterm::event::KeyModifiers::CONTROL)
            {
                mods |= 1;
            }
            if key.modifiers.contains(crossterm::event::KeyModifiers::ALT) {
                mods |= 2;
            }
            if key
                .modifiers
                .contains(crossterm::event::KeyModifiers::SHIFT)
            {
                mods |= 4;
            }

            let code: HxKeyCode = match key.code {
                KeyCode::Char(c) => HxKeyCode::Char(c.to_string().into()),
                KeyCode::Enter => HxKeyCode::Enter,
                KeyCode::Tab => HxKeyCode::Tab,
                KeyCode::Backspace => HxKeyCode::Backspace,
                KeyCode::Delete => HxKeyCode::Delete,
                KeyCode::Esc => HxKeyCode::Esc,

                KeyCode::Up => HxKeyCode::Up,
                KeyCode::Down => HxKeyCode::Down,
                KeyCode::Left => HxKeyCode::Left,
                KeyCode::Right => HxKeyCode::Right,

                KeyCode::Home => HxKeyCode::Home,
                KeyCode::End => HxKeyCode::End,
                KeyCode::PageUp => HxKeyCode::PageUp,
                KeyCode::PageDown => HxKeyCode::PageDown,

                _ => HxKeyCode::Unknown,
            };

            HxEvent::Key(code, mods)
        }
        _ => HxEvent::None,
    }
}

pub fn render(tasks: impl AsRef<str>) {
    if HEADLESS.with(|h| h.get()) {
        // In headless mode, the canonical rendering path is `render_to_string(...)`.
        // Keep `render(...)` a no-op to avoid spamming CI logs when the binary is executed
        // without a real TTY.
        return;
    }

    render_ui(lines_to_ui(tasks.as_ref()));
}

pub fn render_ui(ui: HxUiNode) {
    if HEADLESS.with(|h| h.get()) {
        return;
    }

    TERMINAL.with(|t| {
        let mut borrow = t.borrow_mut();
        let terminal = borrow
            .as_mut()
            .expect("TuiDemo.enter() must be called before render()");

        terminal
            .draw(|frame| {
                let area = frame.size();
                render_node(frame, area, &ui);
            })
            .unwrap();
    })
}

pub fn render_ui_to_string(ui: HxUiNode, width: i32, height: i32) -> String {
    let w = width.max(1) as u16;
    let h = height.max(1) as u16;

    let backend = TestBackend::new(w, h);
    let mut terminal = Terminal::new(backend).unwrap();

    terminal
        .draw(|frame| {
            let area = frame.size();
            render_node(frame, area, &ui);
        })
        .unwrap();

    buffer_to_string(terminal.backend().buffer())
}

#[allow(dead_code)]
fn render_headless(tasks: &str) -> String {
    let ui = lines_to_ui(tasks);

    render_ui_to_string(ui, 60, 10)
}

#[allow(dead_code)]
fn buffer_to_string(buffer: &ratatui::buffer::Buffer) -> String {
    let mut out = String::new();
    let area = buffer.area;
    for y in 0..area.height {
        for x in 0..area.width {
            let cell = buffer.get(x, y);
            out.push_str(cell.symbol());
        }
        out.push('\n');
    }
    out
}

fn lines_to_ui(tasks: &str) -> HxUiNode {
    fn to_string_array<S>(input: &str) -> hxrt::array::Array<S>
    where
        S: From<String> + Clone,
    {
        let values: Vec<S> = input
            .lines()
            .map(|line| S::from(line.to_string()))
            .collect();
        hxrt::array::Array::from_vec(values)
    }

    let items = to_string_array(tasks);
    HxUiNode::List("Todo".to_string().into(), items, -1, HxStyleToken::Normal)
}
