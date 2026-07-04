import rust.Borrow;
import rust.Ref;

class Main {
	static function main():Void {
		var values = [1, 2, 3];
		var leaked:Array<Ref<Array<Int>>> = Borrow.withRef(values, borrowed -> [borrowed]);
		Sys.println(Std.string(leaked));
	}
}
