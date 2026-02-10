package util;

/**
	Tiny fuzzy matcher for the command palette.

	Why
	- We want palette filtering without pulling extra native crates into the example.
	- Deterministic scoring is important for CI snapshots.

	What
	- `score(needle, haystack)` returns `-1` for no match, otherwise a non-negative score.
	- Higher scores are better.

	How
	- Case-insensitive.
	- Substring match wins.
	- Otherwise: simple in-order character match with a small bonus for consecutive runs.
**/
class Fuzzy {
	public static function score(needleRaw: String, haystackRaw: String): Int {
		var needle = needleRaw.toLowerCase();
		var hay = haystackRaw.toLowerCase();

		if (needle.length == 0) return 0;
		if (hay.indexOf(needle) >= 0) return 1000 - hay.length;

		var score = 0;
		var i = 0;
		var run = 0;
		for (j in 0...hay.length) {
			if (i >= needle.length) break;
			if (hay.charAt(j) == needle.charAt(i)) {
				i = i + 1;
				run = run + 1;
				score = score + 10 + run;
			} else {
				run = 0;
			}
		}

		return (i == needle.length) ? score : -1;
	}
}

