use crossterm::event::{self, Event, KeyCode};
use crossterm::terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen};
use crossterm::ExecutableCommand;
use ratatui::backend::{CrosstermBackend, TestBackend};
use ratatui::prelude::*;
use ratatui::widgets::*;
use std::cell::RefCell;
use std::io::{self, Stdout, Write};
use std::time::Duration;

thread_local! {
    static TERMINAL: RefCell<Option<Terminal<CrosstermBackend<Stdout>>>> = RefCell::new(None);
}

// Headless renderer for deterministic snapshots/tests.
#[allow(dead_code)]
pub fn run_frame(frame: i32, tasks: String) {
    println!("--- frame {} ---", frame);
    let rendered = render_headless(&tasks);
    print!("{}", rendered);
}

pub fn enter() {
    enable_raw_mode().unwrap();
    let mut stdout = io::stdout();
    stdout.execute(EnterAlternateScreen).unwrap();
    stdout.flush().ok();

    let backend = CrosstermBackend::new(io::stdout());
    let terminal = Terminal::new(backend).unwrap();
    TERMINAL.with(|t| *t.borrow_mut() = Some(terminal));
}

pub fn exit() {
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
    let lines: Vec<String> = tasks.lines().map(|s| s.to_string()).collect();

    TERMINAL.with(|t| {
        let mut borrow = t.borrow_mut();
        let terminal = borrow.as_mut().expect("TuiDemo.enter() must be called before render()");

        terminal
            .draw(|frame| {
                let items: Vec<ListItem> = lines.iter().map(|l| ListItem::new(l.clone())).collect();
                let list = List::new(items)
                    .block(Block::default().title("Todo").borders(Borders::ALL));
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
            let list = List::new(items)
                .block(Block::default().title("Todo").borders(Borders::ALL));
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
