class Main {
	static inline final INNER_ITERS = 4_000_000;
	static inline final WARMUP_ITERS = 1_024;
	static inline final OUTER_RUNS = 24;

	static function main() {
		var seed = Std.int(Sys.time() * 1000.0) & 0xFFFF;
		var acc = crunch(seed, WARMUP_ITERS);

		var run = 0;
		while (run < OUTER_RUNS) {
			acc = crunch((acc + run) & 0x7FFFFFFF, INNER_ITERS);
			run = run + 1;
		}

		if (acc == -1) {
			Sys.println("unreachable");
		}
	}

	static function crunch(seed:Int, iterations:Int):Int {
		var acc = seed;
		var i = 0;
		while (i < iterations) {
			acc = (acc + (((i * 31) ^ (i >>> 3)) & 0x7FFFFFFF)) & 0x7FFFFFFF;
			i = i + 1;
		}
		return acc;
	}
}
