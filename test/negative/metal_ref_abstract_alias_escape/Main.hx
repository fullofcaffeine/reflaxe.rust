import rust.Borrow;
import rust.Ref;

private abstract BorrowedAlias<T>(Ref<T>) from Ref<T> to Ref<T> {}

class Main {
	static function main():Void {
		var values = [1, 2, 3];
		var leaked:BorrowedAlias<Array<Int>> = Borrow.withRef(values, borrowed -> {
			var alias:BorrowedAlias<Array<Int>> = borrowed;
			return alias;
		});
		Sys.println(Std.string(leaked));
	}
}
