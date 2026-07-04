import rust.Borrow;
import rust.Ref;

class Main {
	static var leaked:Ref<Array<Int>>;

	static function main():Void {
		var values = [1, 2, 3];
		Borrow.withRef(values, borrowed -> {
			leaked = borrowed;
		});
		Sys.println(Std.string(leaked));
	}
}
