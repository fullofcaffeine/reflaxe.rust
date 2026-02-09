/**
	`Date` (reflaxe.rust std override)

	Why
	- The upstream Haxe std declares `Date` as `extern` and relies on each target to provide a
	  concrete implementation (local time accessors, parsing, formatting, time zone offsets).
	- reflaxe.rust only emits Rust modules for user code and for `std/` overrides; without an
	  override, code can typecheck but fail at Rust compile time if `Date` values are emitted.

	What
	- A portable `Date` implementation that matches the Haxe `Date` API:
	  construction from components, timestamp access, local/UTC component getters, timezone offset,
	  `toString`, `now`, `fromTime`, and `fromString`.

	How
	- Stores the Haxe timestamp (`ms since epoch UTC`) as `Float` in a field.
	- Delegates calendar math, parsing, and formatting to the Rust runtime module `hxrt::date`.
	- The runtime uses the host OS locale/timezone data, matching the behavior of other sys targets.
**/
class Date {
	private var ms: Float;

	public function new(year: Int, month: Int, day: Int, hour: Int, min: Int, sec: Int) {
		ms = untyped __rust__(
			"hxrt::date::local_to_ms({0}, {1}, {2}, {3}, {4}, {5}) as f64",
			year,
			month,
			day,
			hour,
			min,
			sec
		);
	}

	public function getTime(): Float {
		return ms;
	}

	public function getHours(): Int {
		return untyped __rust__("hxrt::date::local_hours({0} as i64)", ms);
	}

	public function getMinutes(): Int {
		return untyped __rust__("hxrt::date::local_minutes({0} as i64)", ms);
	}

	public function getSeconds(): Int {
		return untyped __rust__("hxrt::date::local_seconds({0} as i64)", ms);
	}

	public function getFullYear(): Int {
		return untyped __rust__("hxrt::date::local_full_year({0} as i64)", ms);
	}

	public function getMonth(): Int {
		return untyped __rust__("hxrt::date::local_month0({0} as i64)", ms);
	}

	public function getDate(): Int {
		return untyped __rust__("hxrt::date::local_date({0} as i64)", ms);
	}

	public function getDay(): Int {
		return untyped __rust__("hxrt::date::local_day({0} as i64)", ms);
	}

	public function getUTCHours(): Int {
		return untyped __rust__("hxrt::date::utc_hours({0} as i64)", ms);
	}

	public function getUTCMinutes(): Int {
		return untyped __rust__("hxrt::date::utc_minutes({0} as i64)", ms);
	}

	public function getUTCSeconds(): Int {
		return untyped __rust__("hxrt::date::utc_seconds({0} as i64)", ms);
	}

	public function getUTCFullYear(): Int {
		return untyped __rust__("hxrt::date::utc_full_year({0} as i64)", ms);
	}

	public function getUTCMonth(): Int {
		return untyped __rust__("hxrt::date::utc_month0({0} as i64)", ms);
	}

	public function getUTCDate(): Int {
		return untyped __rust__("hxrt::date::utc_date({0} as i64)", ms);
	}

	public function getUTCDay(): Int {
		return untyped __rust__("hxrt::date::utc_day({0} as i64)", ms);
	}

	public function getTimezoneOffset(): Int {
		return untyped __rust__("hxrt::date::timezone_offset_minutes({0} as i64)", ms);
	}

	public function toString(): String {
		return untyped __rust__("hxrt::date::format_local({0} as i64)", ms);
	}

	public static function now(): Date {
		return fromTime(untyped __rust__("hxrt::date::now_ms() as f64"));
	}

	public static function fromTime(t: Float): Date {
		// Construct a placeholder instance, then override its timestamp.
		var d = new Date(1970, 0, 1, 0, 0, 0);
		d.ms = t;
		return d;
	}

	public static function fromString(s: String): Date {
		var t: Float = untyped __rust__("hxrt::date::parse_to_ms({0}.as_str()) as f64", s);
		return fromTime(t);
	}
}
