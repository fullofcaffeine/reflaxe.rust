import rust.MutSlice;
import rust.MutSliceTools;

class Main {
	static function main():Void {
		var values = [1, 2, 3];
		var leaked:MutSlice<Int> = MutSliceTools.with(values, slice -> slice);
		Sys.println(Std.string(leaked));
	}
}
