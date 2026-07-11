private interface CatchableProblem {
	public function label():String;
}

private class NetworkProblem implements CatchableProblem {
	final detail:String;

	public function new(detail:String) {
		this.detail = detail;
	}

	public function label():String {
		return "network:" + detail;
	}
}

class Main {
	static function throwConcrete():Void {
		throw new NetworkProblem("concrete");
	}

	static function throwInterfaceTyped():Void {
		var problem:CatchableProblem = new NetworkProblem("typed");
		throw problem;
	}

	static function throwString():Void {
		throw "plain";
	}

	static function main() {
		try {
			throwConcrete();
		} catch (problem:CatchableProblem) {
			Sys.println(problem.label());
		}

		try {
			throwInterfaceTyped();
		} catch (problem:CatchableProblem) {
			Sys.println(problem.label());
		}

		try {
			throwString();
		} catch (_:CatchableProblem) {
			Sys.println("wrong-interface-catch");
		} catch (message:String) {
			Sys.println("string:" + message);
		}
	}
}
