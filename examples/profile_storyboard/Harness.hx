import profile.RuntimeFactory;
import profile.StoryboardRuntime;

typedef StoryboardSnapshot = {
	profile:String,
	report:String,
	risk:String,
	doneLane:Array<String>,
	moved:Bool,
	missingMove:Bool
};

/**
	Deterministic scenario harness for `examples/profile_storyboard`.
**/
class Harness {
	public static function profileName():String {
		return RuntimeFactory.create().profileName();
	}

	public static function runScenario():StoryboardSnapshot {
		var runtime = RuntimeFactory.create();
		runtime.add("wire compiler", "todo");
		var second = runtime.add("ship docs", "doing");
		runtime.add("final QA", "done");
		var moved = runtime.moveTo(second.id, "done");
		var missingMove = runtime.moveTo(99, "done");

		return {
			profile: runtime.profileName(),
			report: runtime.report(),
			risk: runtime.riskDigest(),
			doneLane: runtime.laneSummary("done"),
			moved: moved,
			missingMove: missingMove
		};
	}

	public static function reportHasExpectedShape():Bool {
		var snapshot = runScenario();
		var lines = snapshot.report.split("\n");
		return lines.length == 3
			&& StringTools.startsWith(lines[0], snapshot.profile + "|todo|")
			&& StringTools.startsWith(lines[1], snapshot.profile + "|doing|")
			&& StringTools.startsWith(lines[2], snapshot.profile + "|done|");
	}

	public static function moveFlowWorks():Bool {
		var snapshot = runScenario();
		if (!snapshot.moved || snapshot.missingMove) {
			return false;
		}
		for (entry in snapshot.doneLane) {
			if (entry.indexOf("2:ship docs") == 0) {
				return true;
			}
		}
		return false;
	}

	public static function riskDigestHasCardCount():Bool {
		var snapshot = runScenario();
		return snapshot.risk.indexOf(snapshot.profile + "|risk|") == 0 && snapshot.risk.indexOf("|cards=3") != -1;
	}

	public static function scenarioOutput():String {
		var snapshot = runScenario();
		return snapshot.report + "\n" + snapshot.risk;
	}
}
