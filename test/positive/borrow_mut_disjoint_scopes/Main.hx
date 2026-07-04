import rust.Borrow;
import rust.HashMap;
import rust.HashMapTools;
import rust.MutSliceTools;
import rust.Vec;
import rust.VecTools;

class Main {
	static function main():Void {
		var map = new HashMap<String, Int>();
		Borrow.withMut(map, first -> {
			HashMapTools.insert(first, "a", 1);
		});
		Borrow.withMut(map, second -> {
			HashMapTools.insert(second, "b", 2);
		});

		var values:Vec<Int> = VecTools.fromArray([1, 2, 3]);
		MutSliceTools.with(values, first -> {
			MutSliceTools.set(first, 0, 10);
		});
		MutSliceTools.with(values, second -> {
			MutSliceTools.set(second, 1, 20);
		});

		trace(HashMapTools.len(map));
	}
}
