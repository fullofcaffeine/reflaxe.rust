class Main {
	static inline final BUFFER_LEN = 4096;
	static inline final OUTER_RUNS = 24;
	static inline final INNER_RUNS = 32;

	static function main() {
		var seed = Std.int(Sys.time() * 1000.0) & 0x7FFFFFFF;
		var acc = crunch(seed);
		if (acc == -1) {
			Sys.println("unreachable");
		}
	}

	static function crunch(seed:Int):Int {
		var bytes = haxe.io.Bytes.alloc(BUFFER_LEN);
		var acc = seed;
		var run = 0;
		while (run < OUTER_RUNS) {
			bytes.fill(0, BUFFER_LEN, (acc + run) & 0xFF);
			var inner = 0;
			while (inner < INNER_RUNS) {
				var pos = (inner * 128) % (BUFFER_LEN - 4);
				var word = (acc + (inner * 1103515245) + (run * 12345)) & 0x7FFFFFFF;
				bytes.setInt32(pos, word);
				acc = (acc ^ bytes.getInt32(pos)) & 0x7FFFFFFF;
				bytes.set(pos + 1, (acc + inner + run) & 0xFF);
				acc = (acc + bytes.get(pos + 1) + bytes.length) & 0x7FFFFFFF;
				inner = inner + 1;
			}
			run = run + 1;
		}
		return acc;
	}
}
