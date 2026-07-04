import rust.MutSliceTools;
import rust.Vec;
import rust.VecTools;

class Main {
	static function main():Void {
		var values:Vec<Int> = VecTools.fromArray([1, 2, 3]);
		MutSliceTools.with(values, first -> {
			MutSliceTools.set(first, 0, 10);
			MutSliceTools.with(values, second -> {
				MutSliceTools.set(second, 1, 20);
			});
		});
	}
}
