class Main {
	static inline final OUTER_RUNS = 18;
	static inline final INNER_RUNS = 40;

	static function main() {
		var acc = crunch();
		if (acc == -1) {
			Sys.println("unreachable");
		}
	}

	static function crunch():Int {
		var acc = 0;
		var run = 0;
		while (run < OUTER_RUNS) {
			var inner = 0;
			while (inner < INNER_RUNS) {
				var payload = {
					id: run * INNER_RUNS + inner,
					label: "json-" + Std.string(run) + "-" + Std.string(inner),
					flags: [inner % 2 == 0, inner % 3 == 0, inner % 5 == 0],
					nested: {
						count: acc + inner,
						tag: "tag-" + Std.string(run & 7)
					}
				};
				var encoded = haxe.Json.stringify(payload);
				acc = (acc + encoded.length) & 0x7FFFFFFF;
				var decoded:Dynamic = haxe.Json.parse(encoded);
				var roundTrip = haxe.Json.stringify(decoded);
				acc = (acc ^ roundTrip.length) & 0x7FFFFFFF;
				inner = inner + 1;
			}
			run = run + 1;
		}
		return acc;
	}
}
