import rust.Borrow;
import rust.Option;
import rust.Vec;
import rust.VecTools;

class Main {
	static function main():Void {
		var values:Vec<Int> = VecTools.fromArray([1, 2, 3]);
		var wrappedLen:Option<Int> = Borrow.withRef(values, borrowed -> {
			var alias = borrowed;
			Some(VecTools.len(alias));
		});
		trace(wrappedLen);
	}
}
