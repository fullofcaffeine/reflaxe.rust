using rust.OptionTools;
using rust.ResultTools;

import rust.Borrow;
import rust.DurationTools;
import rust.HashMap;
import rust.HashMapTools;
import rust.InstantTools;
import rust.MutSliceTools;
import rust.OsStringTools;
import rust.PathBufTools;
import rust.Result;
import rust.SliceTools;
import rust.StrTools;
import rust.Vec;
import rust.VecTools;

class Main {
	static function main(): Void {
		var v = new Vec<Int>();
		v.push(1);
		v.push(2);
		v.push(3);

		var vLen = Borrow.withRef(v, vr -> VecTools.len(vr));
		trace(vLen);

		var hasFirst = Borrow.withRef(v, vr -> VecTools.getRef(vr, 0).isSome());
		trace(hasFirst);

		MutSliceTools.with(v, s -> {
			MutSliceTools.set(s, 0, 10);
		});

		var arr = [1, 2, 3];
		var arrLen = SliceTools.with(arr, s -> SliceTools.len(s));
		trace(arrLen);

		MutSliceTools.with(arr, s -> {
			MutSliceTools.set(s, 1, 99);
		});

		var map = new HashMap<String, Int>();
		Borrow.withMut(map, mm -> {
			HashMapTools.insert(mm, "a", 1);
			HashMapTools.insert(mm, "b", 2);
		});
		var mapLen = Borrow.withRef(map, mr -> HashMapTools.len(mr));
		trace(mapLen);

		var os = OsStringTools.fromString("hello");
		trace(OsStringTools.toStringLossy(os));

		var p = PathBufTools.fromString("foo");
		var p2 = PathBufTools.join(p, "bar.txt");
		trace(PathBufTools.toStringLossy(p2));
		trace(PathBufTools.fileName(p2).isSome());

		var start = InstantTools.now();
		var elapsed = InstantTools.elapsed(start);
		trace(DurationTools.asMillis(elapsed));

		var contains = Borrow.withRef("bootstrap reflaxe.rust", hs -> {
			StrTools.with("reflaxe", needle -> rust.StringTools.contains(hs, needle));
		});
		trace(contains);

		var r: Result<Int, String> = Ok(3);
		trace(r.mapOk(v -> v + 1).isOk());
	}
}
