import rust.Slice;
import rust.SliceTools;

class Main {
	static function main():Void {
		var values = [1, 2, 3];
		var leaked:Slice<Int> = SliceTools.with(values, slice -> slice);
		Sys.println(Std.string(leaked));
	}
}
