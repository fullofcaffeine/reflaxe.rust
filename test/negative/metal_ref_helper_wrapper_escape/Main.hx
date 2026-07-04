import rust.Borrow;
import rust.Ref;

class Main {
	static function box<T>(value:T):Array<T> {
		return [value];
	}

	static function main():Void {
		var values = [1, 2, 3];
		var leaked:Array<Ref<Array<Int>>> = Borrow.withRef(values, borrowed -> {
			var alias = borrowed;
			box(alias);
		});
		Sys.println(Std.string(leaked));
	}
}
