package profile;

import domain.StoryCard;
import rust.Option;
import rust.Result;

typedef NormalizedCardInput = {
	title:String,
	lane:String
};

/**
	Rusty profile implementation: explicit `Result`/`Option` control flow in app logic.
**/
class RustyRuntime implements StoryboardRuntime {
	var nextId:Int = 1;
	var cards:Array<StoryCard> = [];

	public function new() {}

	public function profileName():String {
		return "rusty";
	}

	public function add(title:String, lane:String):StoryCard {
		var normalized = switch (normalizeInput(title, lane)) {
			case Ok(value):
				value;
			case Err(_):
				{
					title: "untitled",
					lane: "todo"
				};
		};

		var card:StoryCard = {
			id: nextId++,
			title: normalized.title,
			lane: normalized.lane,
			score: score(normalized.title, normalized.lane)
		};
		cards.push(card);
		return card;
	}

	public function moveTo(id:Int, lane:String):Bool {
		var laneValue = toKnownLane(lane);
		return switch (indexOfCard(id)) {
			case Some(index):
				var existing = cards[index];
				cards[index] = {
					id: existing.id,
					title: existing.title,
					lane: laneValue,
					score: score(existing.title, laneValue)
				};
				true;
			case None:
				false;
		};
	}

	public function laneSummary(lane:String):Array<String> {
		var laneValue = toKnownLane(lane);
		var out = new Array<String>();
		for (card in cards) {
			if (card.lane == laneValue) {
				out.push(renderCard(card));
			}
		}
		return out;
	}

	public function report():String {
		return [
			profileName() + "|todo|" + laneSummary("todo").join(","),
			profileName() + "|doing|" + laneSummary("doing").join(","),
			profileName() + "|done|" + laneSummary("done").join(",")
		].join("\n");
	}

	public function riskDigest():String {
		var last = switch (lastCard()) {
			case Some(card):
				var value = card.title;
				value;
			case None:
				"<none>";
		};

		var total = 0;
		for (card in cards) {
			total += card.score;
		}
		return profileName() + "|risk|" + total + "|cards=" + cards.length + "|last=" + last;
	}

	function normalizeInput(title:String, lane:String):Result<NormalizedCardInput, String> {
		var titleValue = StringTools.trim(title);
		if (titleValue == "") {
			return Err("empty-title");
		}
		return Ok({
			title: titleValue,
			lane: toKnownLane(lane)
		});
	}

	function toKnownLane(value:String):String {
		var lane = StringTools.trim(value).toLowerCase();
		return lane == "todo" || lane == "doing" || lane == "done" ? lane : "todo";
	}

	function indexOfCard(id:Int):Option<Int> {
		for (index in 0...cards.length) {
			if (cards[index].id == id) {
				return Some(index);
			}
		}
		return None;
	}

	function lastCard():Option<StoryCard> {
		if (cards.length == 0) {
			return None;
		}
		return Some(cards[cards.length - 1]);
	}

	function score(title:String, lane:String):Int {
		return title.length * 31 + lane.length * 7 + nextId;
	}

	function renderCard(card:StoryCard):String {
		return card.id + ":" + card.title + "#" + card.score;
	}
}
