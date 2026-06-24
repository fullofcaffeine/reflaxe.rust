package rust;

/**
 * `rust.SystemTimeTools`
 *
 * Why
 * - Metal/no-hxrt users need typed access to Rust wall-clock primitives without app-side
 *   raw `__rust__`.
 * - Portable `Date` remains the right API for Haxe calendar/date semantics; this facade is
 *   Rust-native interop for code that intentionally speaks `std::time`.
 *
 * What
 * - Small convenience helpers around the direct `rust.SystemTime` stdlib extern.
 * - Helpers for Unix timestamp conversion.
 *
 * How
 * - `durationSinceUnixEpoch` and `unixMillis` saturate to zero for pre-epoch inputs so
 *   callers can use a simple non-throwing API in `rust_no_hxrt` code.
 */
class SystemTimeTools {
	public static inline function durationSinceUnixEpoch(t:SystemTime):Duration {
		return switch (t.durationSince(SystemTime.UNIX_EPOCH)) {
			case Ok(duration):
				duration;
			case Err(_):
				DurationTools.fromMillis(0);
		}
	}

	public static inline function unixMillis(t:SystemTime):Float {
		var duration = durationSinceUnixEpoch(t);
		return DurationTools.asMillis(duration);
	}

	public static inline function nowUnixMillis():Float {
		return unixMillis(SystemTime.now());
	}
}
