import rust.Borrow;
import rust.MutRef;

class Main {
	static function main():Void {
		var values = [1, 2, 3];
		var leaked:MutRef<Array<Int>> = Borrow.withMut(values, borrowed -> borrowed);
		Sys.println(Std.string(leaked));
	}
}
