import rust.Borrow;
import rust.Option;
import rust.Ref;

class Main {
	static function main():Void {
		var values = [1, 2, 3];
		var leaked:Option<Ref<Array<Int>>> = Borrow.withRef(values, borrowed -> {
			var alias = borrowed;
			Some(alias);
		});
		Sys.println(Std.string(leaked));
	}
}
