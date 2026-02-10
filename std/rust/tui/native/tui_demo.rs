use crossterm::event::{self, Event, KeyCode};
use crossterm::terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen};
use crossterm::ExecutableCommand;
use ratatui::backend::{CrosstermBackend, TestBackend};
use ratatui::prelude::*;
use ratatui::widgets::*;
use std::cell::{Cell, RefCell};
use std::io::{self, IsTerminal, Stdout, Write};
use std::time::Duration;

thread_local! {
    static TERMINAL: RefCell<Option<Terminal<CrosstermBackend<Stdout>>>> = RefCell::new(None);
    static HEADLESS: Cell<bool> = Cell::new(false);
    static HEADLESS_SET: Cell<bool> = Cell::new(false);
}

// High-level events and key codes are defined in Haxe under `std/rust/tui/*` and compiled to Rust
// modules named `rust_tui_*`.
use crate::rust_tui_event::Event as HxEvent;
use crate::rust_tui_key_code::KeyCode as HxKeyCode;
use crate::rust_tui_ui_node::UiNode as HxUiNode;
use crate::rust_tui_style_token::StyleToken as HxStyleToken;
use crate::rust_tui_layout_dir::LayoutDir as HxLayoutDir;
use crate::rust_tui_constraint::Constraint as HxConstraint;

fn style_for(token: &HxStyleToken) -> Style {
    match token.clone() {
        HxStyleToken::Normal => Style::default(),
        HxStyleToken::Muted => Style::default().fg(Color::DarkGray),
        HxStyleToken::Title => Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD),
        HxStyleToken::Accent => Style::default().fg(Color::Magenta).add_modifier(Modifier::BOLD),
        HxStyleToken::Selected => Style::default()
            .fg(Color::Black)
            .bg(Color::LightCyan)
            .add_modifier(Modifier::BOLD),
        HxStyleToken::Success => Style::default().fg(Color::Green).add_modifier(Modifier::BOLD),
        HxStyleToken::Warning => Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD),
        HxStyleToken::Danger => Style::default().fg(Color::Red).add_modifier(Modifier::BOLD),
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
            let areas = Layout::default().direction(direction).constraints(cons).split(area);

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
                .map(|t| Line::from(vec![Span::raw(t)]))
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
            let list_items: Vec<ListItem> = items.iter().map(ListItem::new).collect();
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

            let text = body.iter().collect::<Vec<String>>().join("\n");
            let p = Paragraph::new(text)
                .wrap(Wrap { trim: false })
                .style(style_for(&HxStyleToken::Normal));
            frame.render_widget(p, inner);
        }
    }
}

// Deterministic renderer for tests/snapshots.
#[allow(dead_code)]
pub fn run_frame(frame: i32, tasks: String) {
    println!("--- frame {} ---", frame);
    let rendered = render_headless(&tasks);
    print!("{}", rendered);
}

// Deterministic renderer for tests/snapshots (no global state, no stdout).
#[allow(dead_code)]
pub fn render_to_string(tasks: String) -> String {
    render_headless(&tasks)
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
            if key.modifiers.contains(crossterm::event::KeyModifiers::CONTROL) {
                mods |= 1;
            }
            if key.modifiers.contains(crossterm::event::KeyModifiers::ALT) {
                mods |= 2;
            }
            if key.modifiers.contains(crossterm::event::KeyModifiers::SHIFT) {
                mods |= 4;
            }

            let code: HxKeyCode = match key.code {
                KeyCode::Char(c) => HxKeyCode::Char(c.to_string()),
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

pub fn render(tasks: String) {
    if HEADLESS.with(|h| h.get()) {
        // In headless mode, the canonical rendering path is `render_to_string(...)`.
        // Keep `render(...)` a no-op to avoid spamming CI logs when the binary is executed
        // without a real TTY.
        return;
    }

    render_ui(lines_to_ui(tasks));
}

pub fn render_ui(ui: HxUiNode) {
    if HEADLESS.with(|h| h.get()) {
        return;
    }

    TERMINAL.with(|t| {
        let mut borrow = t.borrow_mut();
        let terminal = borrow.as_mut().expect("TuiDemo.enter() must be called before render()");

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
    let ui = lines_to_ui(tasks.to_string());

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

fn lines_to_ui(tasks: String) -> HxUiNode {
    let lines: Vec<String> = tasks.lines().map(|s| s.to_string()).collect();
    let items = hxrt::array::Array::<String>::from_vec(lines);

    HxUiNode::List(String::from("Todo"), items, -1, HxStyleToken::Normal)
}
