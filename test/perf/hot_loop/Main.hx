class Main {
	static inline final HOT_LOOP_N = 4_000_000;

	static function main() {
		var seed = Std.int(Sys.time() * 1000.0) & 0xFFFF;
		var acc = seed;
		var i = 0;
		while (i < HOT_LOOP_N) {
			acc = (acc + (((i * 31) ^ (i >>> 3)) & 0x7FFFFFFF)) & 0x7FFFFFFF;
			i = i + 1;
		}
		if (acc == (seed - 1)) {
			Sys.println("unreachable");
		}
	}
}
