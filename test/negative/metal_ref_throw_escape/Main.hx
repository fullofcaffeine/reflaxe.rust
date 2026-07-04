import rust.Borrow;

class Main {
	static function main():Void {
		var values = [1, 2, 3];
		Borrow.withRef(values, borrowed -> {
			var alias = borrowed;
			throw alias;
		});
	}
}
