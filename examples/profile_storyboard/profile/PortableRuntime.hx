package profile;

import domain.StoryCard;

/**
	Portable profile implementation: plain typed Haxe data and loops.
**/
class PortableRuntime implements StoryboardRuntime {
	var nextId:Int = 1;
	var cards:Array<StoryCard> = [];

	public function new() {}

	public function profileName():String {
		return "portable";
	}

	public function add(title:String, lane:String):StoryCard {
		var laneValue = normalizeLane(lane);
		var titleValue = normalizeTitle(title);
		var card:StoryCard = {
			id: nextId++,
			title: titleValue,
			lane: laneValue,
			score: score(titleValue, laneValue)
		};
		cards.push(card);
		return card;
	}

	public function moveTo(id:Int, lane:String):Bool {
		var laneValue = normalizeLane(lane);
		for (index in 0...cards.length) {
			if (cards[index].id == id) {
				var current = cards[index];
				cards[index] = {
					id: current.id,
					title: current.title,
					lane: laneValue,
					score: score(current.title, laneValue)
				};
				return true;
			}
		}
		return false;
	}

	public function laneSummary(lane:String):Array<String> {
		var laneValue = normalizeLane(lane);
		var out = new Array<String>();
		for (card in cards) {
			if (card.lane == laneValue) {
				out.push(card.id + ":" + card.title + "#" + card.score);
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
		var risk = 0;
		for (card in cards) {
			risk += card.score;
		}
		return profileName() + "|risk|" + risk + "|cards=" + cards.length;
	}

	function normalizeLane(value:String):String {
		var lane = StringTools.trim(value).toLowerCase();
		return lane == "todo" || lane == "doing" || lane == "done" ? lane : "todo";
	}

	function normalizeTitle(value:String):String {
		var title = StringTools.trim(value);
		return title == "" ? "untitled" : title;
	}

	function score(title:String, lane:String):Int {
		return title.length * 3 + lane.length;
	}
}
