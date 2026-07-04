import rust.Borrow;
import rust.Ref;

class Main {
	static var later:Void->Ref<Array<Int>>;

	static function main():Void {
		var values = [1, 2, 3];
		Borrow.withRef(values, borrowed -> {
			var alias = borrowed;
			later = () -> alias;
		});
		Sys.println(Std.string(later));
	}
}
