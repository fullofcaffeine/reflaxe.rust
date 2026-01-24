package rust;

/**
 * InstantTools
 *
 * Framework helpers for `rust.Instant`.
 */
class InstantTools {
	public static function now(): Instant {
		return untyped __rust__("std::time::Instant::now()");
	}

	public static function elapsed(i: Ref<Instant>): Duration {
		return untyped __rust__("({0}).elapsed()", i);
	}

	public static function elapsedMillis(i: Ref<Instant>): Float {
		return untyped __rust__(
			"({0}).elapsed().as_secs_f64() * 1000.0",
			i
		);
	}
}
