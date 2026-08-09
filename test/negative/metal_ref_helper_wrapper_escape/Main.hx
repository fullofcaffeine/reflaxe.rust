import rust.Borrow;
import rust.Ref;

private abstract Deep<T>(Array<Array<T>>) from Array<Array<T>> to Array<Array<T>> {}
private typedef D1<T> = Deep<T>;
private typedef D2<T> = Deep<D1<T>>;
private typedef D3<T> = Deep<D2<T>>;
private typedef D4<T> = Deep<D3<T>>;
private typedef D5<T> = Deep<D4<T>>;
private typedef D6<T> = Deep<D5<T>>;

class Main {
	static function box<T>(value:T):Deep<T> {
		return [[value]];
	}

	static function main():Void {
		var values = [1, 2, 3];
		var leaked:D6<Ref<Array<Int>>> = Borrow.withRef(values, borrowed -> {
			var alias = borrowed;
			box(box(box(box(box(box(alias))))));
		});
		Sys.println(Std.string(leaked));
	}
}
