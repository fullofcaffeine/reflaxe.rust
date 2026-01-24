use ratatui::backend::TestBackend;
use ratatui::prelude::*;
use ratatui::widgets::*;

pub fn run_frame(frame: i32, tasks: String) {
    println!("--- frame {} ---", frame);
    let rendered = render_headless(&tasks);
    print!("{}", rendered);
}

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

