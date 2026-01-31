import rust.Borrow;
import rust.SliceTools;
import rust.StrTools;
import rust.StringTools;
import rust.Vec;
import rust.VecTools;

class Main {
	static function main(): Void {
		var hay = "hello";
		var needle = "ell";
		Borrow.withRef(hay, h -> {
			StrTools.with(needle, n -> {
				trace(StringTools.contains(h, n));
			});
		});

		var v = new Vec<Int>();
		v.push(1);
		v.push(2);
		v.push(3);

		var sum = 0;
		for (x in VecTools.toArray(v.clone())) sum = sum + x;
		trace(sum);
		trace(VecTools.len(v));

		Borrow.withRef(v, vr -> {
			var s = SliceTools.fromVec(vr);
			var sum2 = 0;
			for (x in SliceTools.toArray(s)) sum2 = sum2 + x;
			trace(sum2);
			trace(SliceTools.len(s));
		});
	}
}
