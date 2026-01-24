class Main {
	static function main() {
		var a = Action.Move(2);
		var s = switch (a) {
			case Move(d): "move:" + d;
			case Toggle: "toggle";
		}
		trace(s);
	}
}
