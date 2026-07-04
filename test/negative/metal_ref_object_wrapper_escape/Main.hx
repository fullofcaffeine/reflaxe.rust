import rust.Borrow;
import rust.Ref;

typedef WrappedRef = {
	var borrowed:Ref<Array<Int>>;
}

class Main {
	static function main():Void {
		var values = [1, 2, 3];
		var leaked:WrappedRef = Borrow.withRef(values, borrowed -> {
			var alias = borrowed;
			{borrowed: alias};
		});
		Sys.println(Std.string(leaked));
	}
}
