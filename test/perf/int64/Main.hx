import haxe.Int64;

class Main {
	static inline final INNER_ITERS = 80000;
	static inline final OUTER_RUNS = 40;

	static function main() {
		var seed = Int64.make(0x13579BDF, 0x2468ACE0);
		var acc = crunch(seed);
		if (Int64.compare(acc, Int64.make(-1, -1)) == 0) {
			Sys.println("unreachable");
		}
	}

	static function crunch(seed:Int64):Int64 {
		var acc = seed;
		var run = 0;
		while (run < OUTER_RUNS) {
			var i = 0;
			while (i < INNER_ITERS) {
				var step = Int64.ofInt((i * 31) ^ (i >>> 3) ^ run);
				acc = (acc + step) ^ (step << (i & 7));
				acc = acc - (step >>> 1);
				acc = acc + Int64.ofInt(run + i);
				i = i + 1;
			}
			run = run + 1;
		}
		return acc;
	}
}
