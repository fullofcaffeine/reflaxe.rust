package profile;

import domain.StoryCard;

/**
	Idiomatic profile implementation: still portable semantics, cleaner composable helpers.
**/
class IdiomaticRuntime implements StoryboardRuntime {
	var nextId:Int = 1;
	var cards:Array<StoryCard> = [];

	public function new() {}

	public function profileName():String {
		return "idiomatic";
	}

	public function add(title:String, lane:String):StoryCard {
		final laneValue = normalizedLane(lane);
		final titleValue = normalizedTitle(title);
		final card:StoryCard = {
			id: nextId++,
			title: titleValue,
			lane: laneValue,
			score: score(titleValue, laneValue)
		};
		cards.push(card);
		return card;
	}

	public function moveTo(id:Int, lane:String):Bool {
		final laneValue = normalizedLane(lane);
		for (index in 0...cards.length) {
			if (cards[index].id == id) {
				final existing = cards[index];
				cards[index] = {
					id: existing.id,
					title: existing.title,
					lane: laneValue,
					score: score(existing.title, laneValue)
				};
				return true;
			}
		}
		return false;
	}

	public function laneSummary(lane:String):Array<String> {
		final laneValue = normalizedLane(lane);
		final laneCards = cards.filter(card -> card.lane == laneValue);
		return [for (card in laneCards) renderCard(card)];
	}

	public function report():String {
		final lanes = ["todo", "doing", "done"];
		final lines = [
			for (lane in lanes) profileName() + "|" + lane + "|" + laneSummary(lane).join(",")
		];
		return lines.join("\n");
	}

	public function riskDigest():String {
		var total = 0;
		for (card in cards) {
			total += card.score;
		}
		final doneCount = cards.filter(card -> card.lane == "done").length;
		return profileName() + "|risk|" + total + "|cards=" + cards.length + "|done=" + doneCount;
	}

	function normalizedLane(value:String):String {
		final lane = StringTools.trim(value).toLowerCase();
		return lane == "todo" || lane == "doing" || lane == "done" ? lane : "todo";
	}

	function normalizedTitle(value:String):String {
		final title = StringTools.trim(value);
		return title == "" ? "untitled" : title;
	}

	function score(title:String, lane:String):Int {
		var sum = 0;
		final bytes = haxe.io.Bytes.ofString(title + ":" + lane);
		for (index in 0...bytes.length) {
			sum += bytes.get(index);
		}
		return sum % 257;
	}

	function renderCard(card:StoryCard):String {
		return card.id + ":" + card.title + "#" + card.score;
	}
}
