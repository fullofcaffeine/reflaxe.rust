package profile;

import domain.StoryCard;

/**
	Shared runtime contract for the profile storyboard example.

	Why
	- Keeps the scenario fixed while runtime implementations vary by profile style.

	What
	- `add`/`moveTo` mutate board state.
	- `laneSummary`/`report` expose deterministic textual output for tests.
	- `riskDigest` emits a compact profile-specific metric line.
**/
interface StoryboardRuntime {
	function profileName():String;
	function add(title:String, lane:String):StoryCard;
	function moveTo(id:Int, lane:String):Bool;
	function laneSummary(lane:String):Array<String>;
	function report():String;
	function riskDigest():String;
}
