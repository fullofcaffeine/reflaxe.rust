import rust.Borrow;
import rust.PathBufTools;
import rust.Vec;

class Main {
	static function inspect(value:Dynamic):String {
		return Std.string(value);
	}

	static function main():Void {
		var count = 7;
		var label = "hello";
		var numbers = new Vec<Int>();
		numbers.push(9);
		var path = PathBufTools.fromString("folder");
		var copied = Borrow.withRef(count, borrowed -> inspect(borrowed));
		var cloned = Borrow.withRef(label, borrowed -> inspect(borrowed));
		var clonedNumbers = Borrow.withRef(numbers, borrowed -> inspect(borrowed));
		var clonedPath = Borrow.withRef(path, borrowed -> inspect(borrowed));
		var anonymousCreated = Borrow.withRef(count, countRef -> Borrow.withRef(label, labelRef -> {
			var holder = {count: countRef, label: labelRef};
			holder != null;
		}));
		Sys.println(copied + "|" + cloned + "|" + (clonedNumbers.length > 0 && clonedPath.length > 0 && anonymousCreated));
	}
}
