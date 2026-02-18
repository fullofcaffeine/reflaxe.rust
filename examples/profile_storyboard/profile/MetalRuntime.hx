package profile;

import domain.StoryCard;
import rust.Option;
import rust.Result;
import rust.metal.Code;

typedef MetalCardInput = {
	title:String,
	lane:String
};

/**
	Metal profile implementation: Rusty-style typed flow plus typed low-level snippets via `Code`.
**/
class MetalRuntime implements StoryboardRuntime {
	var nextId:Int = 1;
	var cards:Array<StoryCard> = [];

	public function new() {}

	public function profileName():String {
		return "metal";
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
		var total = 0;
		for (card in cards) {
			total += card.score;
		}
		var last = switch (lastCard()) {
			case Some(card):
				var value = card.title;
				value;
			case None:
				"<none>";
		};
		return profileName() + "|risk|" + total + "|cards=" + cards.length + "|last=" + last;
	}

	function normalizeInput(title:String, lane:String):Result<MetalCardInput, String> {
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
		Code.stmt("let _ = (&{0}, &{1});", title, lane);
		var titleLen:Int = Code.expr("{0}.len() as i32", title);
		var laneLen:Int = Code.expr("{0}.len() as i32", lane);
		var mixed:Int = Code.expr("((({0} as i64) * 73 + ({1} as i64) * 17 + ({2} as i64)) % 1000003) as i32", titleLen, laneLen, nextId);
		return mixed;
	}

	function renderCard(card:StoryCard):String {
		return card.id + ":" + card.title + "#" + card.score;
	}
}
