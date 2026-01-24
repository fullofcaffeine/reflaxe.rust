import rust.Borrow;
import rust.Slice;
import rust.SliceTools;
import rust.Vec;

class Main {
	static function main() {
		var v = new Vec<Int>();
		v.push(1);
		v.push(2);

		var sum = 0;
		for (x in v) {
			sum = sum + x;
		}

		var sum2 = 0;
		Borrow.withRef(v, function(r) {
			var s: Slice<Int> = SliceTools.fromVec(r);
			for (y in s) {
				sum2 = sum2 + y;
			}
		});

		trace(sum + sum2);
	}
}
