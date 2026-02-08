use crossterm::event::{self, Event, KeyCode};
use crossterm::terminal::{
    disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen,
};
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

pub fn render(tasks: String) {
    if HEADLESS.with(|h| h.get()) {
        // In headless mode, the canonical rendering path is `render_to_string(...)`.
        // Keep `render(...)` a no-op to avoid spamming CI logs when the binary is executed
        // without a real TTY.
        return;
    }

    let lines: Vec<String> = tasks.lines().map(|s| s.to_string()).collect();

    TERMINAL.with(|t| {
        let mut borrow = t.borrow_mut();
        let terminal = borrow
            .as_mut()
            .expect("TuiDemo.enter() must be called before render()");

        terminal
            .draw(|frame| {
                let items: Vec<ListItem> = lines.iter().map(|l| ListItem::new(l.clone())).collect();
                let list =
                    List::new(items).block(Block::default().title("Todo").borders(Borders::ALL));
                frame.render_widget(list, frame.size());
            })
            .unwrap();
    });
}

#[allow(dead_code)]
fn render_headless(tasks: &str) -> String {
    let lines: Vec<&str> = tasks.lines().collect();

    let backend = TestBackend::new(60, 10);
    let mut terminal = Terminal::new(backend).unwrap();

    terminal
        .draw(|frame| {
            let items: Vec<ListItem> = lines
                .iter()
                .map(|l| ListItem::new((*l).to_string()))
                .collect();
            let list = List::new(items).block(Block::default().title("Todo").borders(Borders::ALL));
            frame.render_widget(list, frame.size());
        })
        .unwrap();

    buffer_to_string(terminal.backend().buffer())
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
