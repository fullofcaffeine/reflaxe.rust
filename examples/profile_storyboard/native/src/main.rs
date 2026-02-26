#[derive(Clone)]
struct StoryCard {
    id: i32,
    title: String,
    lane: String,
    score: i32,
}

struct MetalCardInput {
    title: String,
    lane: String,
}

struct MetalRuntime {
    next_id: i32,
    cards: Vec<StoryCard>,
}

impl MetalRuntime {
    fn new() -> Self {
        Self {
            next_id: 1,
            cards: Vec::new(),
        }
    }

    fn add(&mut self, title: &str, lane: &str) -> StoryCard {
        let normalized = self.normalize_input(title, lane).unwrap_or(MetalCardInput {
            title: "untitled".to_owned(),
            lane: "todo".to_owned(),
        });

        let id = self.next_id;
        self.next_id += 1;
        let score = self.score(&normalized.title, &normalized.lane);
        let card = StoryCard {
            id,
            title: normalized.title,
            lane: normalized.lane,
            score,
        };
        self.cards.push(card.clone());
        card
    }

    fn move_to(&mut self, id: i32, lane: &str) -> bool {
        let lane_value = self.to_known_lane(lane);
        if let Some(index) = self.index_of_card(id) {
            let existing = self.cards[index].clone();
            self.cards[index] = StoryCard {
                id: existing.id,
                title: existing.title.clone(),
                lane: lane_value.clone(),
                score: self.score(&existing.title, &lane_value),
            };
            true
        } else {
            false
        }
    }

    fn lane_summary(&self, lane: &str) -> Vec<String> {
        let lane_value = self.to_known_lane(lane);
        self.cards
            .iter()
            .filter(|card| card.lane == lane_value)
            .map(Self::render_card)
            .collect()
    }

    fn report(&self) -> String {
        [
            format!("metal|todo|{}", self.lane_summary("todo").join(",")),
            format!("metal|doing|{}", self.lane_summary("doing").join(",")),
            format!("metal|done|{}", self.lane_summary("done").join(",")),
        ]
        .join("\n")
    }

    fn risk_digest(&self) -> String {
        let total: i32 = self.cards.iter().map(|card| card.score).sum();
        let last = self
            .cards
            .last()
            .map(|card| card.title.as_str())
            .unwrap_or("<none>");
        format!("metal|risk|{total}|cards={}|last={last}", self.cards.len())
    }

    fn normalize_input(&self, title: &str, lane: &str) -> Result<MetalCardInput, String> {
        let title_value = title.trim();
        if title_value.is_empty() {
            return Err("empty-title".to_owned());
        }
        Ok(MetalCardInput {
            title: title_value.to_owned(),
            lane: self.to_known_lane(lane),
        })
    }

    fn to_known_lane(&self, value: &str) -> String {
        let lane = value.trim().to_lowercase();
        if lane == "todo" || lane == "doing" || lane == "done" {
            lane
        } else {
            "todo".to_owned()
        }
    }

    fn index_of_card(&self, id: i32) -> Option<usize> {
        self.cards.iter().position(|card| card.id == id)
    }

    fn score(&self, title: &str, lane: &str) -> i32 {
        let title_len = title.chars().count() as i32;
        let lane_len = lane.chars().count() as i32;
        (title_len * 73 + lane_len * 17 + self.next_id) % 1_000_003
    }

    fn render_card(card: &StoryCard) -> String {
        format!("{}:{}#{}", card.id, card.title, card.score)
    }
}

fn main() {
    let mut runtime = MetalRuntime::new();
    runtime.add("wire compiler", "todo");
    let second = runtime.add("ship docs", "doing");
    runtime.add("final QA", "done");
    runtime.move_to(second.id, "done");
    runtime.move_to(99, "done");

    println!("{}", runtime.report());
    println!("{}", runtime.risk_digest());
}
