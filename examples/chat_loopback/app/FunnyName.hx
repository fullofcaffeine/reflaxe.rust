package app;

/**
 * FunnyName
 *
 * Why
 * - Multi-instance demo clients should auto-identify with playful names without manual setup.
 *
 * What
 * - Deterministic funny-name generator from an integer seed.
 *
 * How
 * - Combines adjective + creature + numeric suffix using a tiny LCG step sequence.
 */
class FunnyName {
	static inline final TIME_WINDOW_SECONDS:Float = 2048.0;

	static final ADJECTIVES = [
		"wobbly",
		"turbo",
		"noisy",
		"cosmic",
		"snappy",
		"glitchy",
		"bouncy",
		"spicy",
		"zesty",
		"fuzzy",
	];

	static final CREATURES = [
		"otter", "ferret", "yak", "badger", "lemur", "panda", "crab", "goose", "mole", "gecko",
	];

	public static function generate(seed:Int):String {
		var state = seed & 0x7fffffff;
		state = step(state);
		var adjective = ADJECTIVES[state % ADJECTIVES.length];
		state = step(state);
		var creature = CREATURES[state % CREATURES.length];
		state = step(state);
		var suffix = 100 + (state % 900);
		return adjective + "_" + creature + "_" + suffix;
	}

	/**
	 * Why
	 * - Chat instances launched close together should still get distinct default identities.
	 * - Direct `Std.int(Sys.time() * 1000.0)` can saturate on large epoch values in Rust, which
	 *   collapses seeds and causes repeated names.
	 *
	 * What
	 * - Builds a bounded per-launch seed from folded time + port + caller-provided salt.
	 *
	 * How
	 * - Folds wall-clock time into a safe Int range first, then xors and xorshifts before
	 *   forwarding into `generate(...)`.
	 */
	public static function generateAuto(nowSeconds:Float, port:Int, salt:Int):String {
		var foldedTime = foldTimeForSeed(nowSeconds);
		var mixed = foldedTime ^ (port & 0x7fffffff) ^ (salt & 0x7fffffff);
		return generate(step(mixed));
	}

	/**
	 * Convenience entrypoint for app startup identity generation.
	 */
	public static function generateAutoForPort(port:Int):String {
		var now = Sys.time();
		var salt = foldTimeForSeed((now * 0.731) + 13.0) ^ foldTimeForSeed(now + 0.137);
		return generateAuto(now, port, salt);
	}

	/**
	 * Folds absolute wall-clock time into a bounded Int-safe seed window.
	 */
	public static function foldTimeForSeed(nowSeconds:Float):Int {
		var wrapped = nowSeconds % TIME_WINDOW_SECONDS;
		if (wrapped < 0) {
			wrapped = wrapped + TIME_WINDOW_SECONDS;
		}
		return Std.int(wrapped * 1000000.0);
	}

	static inline function step(state:Int):Int {
		// xorshift avoids debug-overflow traps in Rust while staying deterministic.
		var next = state;
		next = next ^ (next << 13);
		next = next ^ (next >> 17);
		next = next ^ (next << 5);
		return next & 0x7fffffff;
	}
}
