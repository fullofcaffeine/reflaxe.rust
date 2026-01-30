import rust.MutSliceTools;
import rust.SliceTools;

class Main {
	static function main(): Void {
		var xs = [1, 2, 3];

		SliceTools.with(xs, s -> {
			Sys.println(SliceTools.len(s));
		});

		MutSliceTools.with(xs, s -> {
			MutSliceTools.set(s, 1, 99);
		});

		Sys.println(xs[1]);
	}
}
