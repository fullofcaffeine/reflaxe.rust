package rust;

/**
 * DurationTools
 *
 * Framework helpers for `rust.Duration`.
 */
class DurationTools {
	public static function fromMillis(ms: Int): Duration {
		return untyped __rust__(
			"std::time::Duration::from_millis(({0}).max(0) as u64)",
			ms
		);
	}

	public static function fromSecs(secs: Int): Duration {
		return untyped __rust__(
			"std::time::Duration::from_secs(({0}).max(0) as u64)",
			secs
		);
	}

	public static function asMillis(d: Duration): Float {
		return untyped __rust__("{0}.as_secs_f64() * 1000.0", d);
	}

	public static function sleep(d: Duration): Void {
		untyped __rust__("{ std::thread::sleep({0}); }", d);
	}
}

