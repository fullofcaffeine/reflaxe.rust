class Main {
	static function main() {
		var token = LaneAliasToken.Right;
		var label = switch (token) {
			case Left: "left";
			case Right: "right";
		};
		Sys.println(label);
	}
}
