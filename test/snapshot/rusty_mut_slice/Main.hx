import rust.MutSliceTools;
import rust.Vec;

class Main {
	static function main(): Void {
		var v = new Vec<Int>();
		v.push(1);
		v.push(2);
		v.push(3);

		MutSliceTools.with(v, s -> {
			MutSliceTools.set(s, 1, 99);
		});

		var sum = 0;
		for (x in v) sum = sum + x;
		trace(sum);
	}
}

