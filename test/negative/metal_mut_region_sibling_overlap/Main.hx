import rust.Borrow;
import rust.MutSliceTools;
import rust.Vec;
import rust.VecTools;

class Main {
	static function main():Void {
		var values:Vec<Int> = VecTools.fromArray([1, 2, 3]);
		Borrow.withMut(values, outer -> {
			MutSliceTools.with(values, slice -> {
				MutSliceTools.set(slice, 0, 10);
			});
			Borrow.withMut(values, inner -> {
				Sys.println(Std.string(inner));
			});
		});
	}
}
