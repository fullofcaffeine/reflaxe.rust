import rust.Borrow;
import rust.Vec;
import rust.VecTools;

class Main {
	static function main():Void {
		var values:Vec<Int> = VecTools.fromArray([1, 2, 3]);
		var len = Borrow.withRef(values, borrowed -> {
			var alias = borrowed;
			VecTools.len(alias);
		});
		trace(len);
	}
}
