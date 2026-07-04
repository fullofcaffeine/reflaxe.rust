import rust.Borrow;
import rust.Ref;

class Main {
	static function main():Void {
		var values = [1, 2, 3];
		var leaked:Ref<Array<Int>> = Borrow.withRef(values, borrowed -> {
			var alias = borrowed;
			alias;
		});
		Sys.println(Std.string(leaked));
	}
}
