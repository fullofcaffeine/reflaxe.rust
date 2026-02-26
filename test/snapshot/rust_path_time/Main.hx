import rust.DurationTools;
import rust.InstantTools;
import rust.OsStringTools;
import rust.PathBufTools;

class Main {
	static function main() {
		var base = PathBufTools.fromString("tmp");
		var child = PathBufTools.join(base, "example.txt");
		var pushed = PathBufTools.push(base, "nested");

		var childStr = PathBufTools.toStringLossy(child);
		var pushedName = PathBufTools.fileName(pushed);

		var os = OsStringTools.fromString(childStr);
		var osLossy = OsStringTools.toStringLossy(os);

		var started = InstantTools.now();
		var d = DurationTools.fromMillis(25);
		DurationTools.sleep(d);
		var elapsedMs = InstantTools.elapsedMillis(started);

		// Keep values "used" so rustc doesn't optimize them away and trigger unused warnings.
		if (osLossy != "" && elapsedMs >= 0.0) {
			switch (pushedName) {
				case Some(name):
					trace(name);
				case None:
					trace(osLossy);
			}
		}
	}
}
