class RustRepresentationTypeFixture {
	public function new() {
		var constructorDynamic:Dynamic = 424242;
	}

	static var scalar:Int;
	static var enumValue:RustRepresentationFixtureChoice;
	static var nativeOwned:rust.Vec<Int>;
	static var nativeOwnedDynamic:rust.Vec<Dynamic>;
	static var sharedIdentity:RustRepresentationFixtureNode;
	static var polymorphic:RustRepresentationFixtureContract;
	static var borrowed:rust.Ref<Int>;
	static var borrowedArrayShape:Array<rust.Ref<Int>>;
	static var anonymousSiblings:RustRepresentationAnonymousPair<{left:Int}, {right:Dynamic}>;
	static var borrowedNativeOwned:rust.Ref<rust.Vec<Int>>;
	static var borrowedPath:rust.Ref<rust.PathBuf>;
	static var borrowedNativeHandle:rust.Ref<rust.net.TcpStream>;
	static var nullableBorrowed:Null<rust.Ref<Int>>;
	static var nativeHandle:rust.net.TcpStream;
	static var dynamicValue:Dynamic;
	static var classHandle:Class<RustRepresentationFixtureNode>;
	static var enumHandle:Enum<RustRepresentationFixtureChoice>;
	static var stringValue:String;
	static var arrayValue:Array<Int>;
	static var anonymousValue:{value:Int};
	static var functionValue:Int->String;
	static var iteratorValue:Iterator<Int>;
	static var nullableValue:Null<Int>;
	static var mapValue:Map<String, String>;
	static function consumeDynamic(value:Dynamic):Void {}
	static function exerciseDynamicBoundaries(flag:Bool):Dynamic {
		consumeDynamic(1);
		consumeDynamic(new RustRepresentationFixtureNode());
		consumeDynamic(RustRepresentationFixtureChoice.First);
		// The compiler copies the value behind an immutable rust.Ref before boxing; the lexical
		// borrow token itself must never be described as escaping into Dynamic.
		consumeDynamic(borrowed);
		haxe.Json.stringify(2);
		var local:Dynamic = 3;
		local = 4;
		var constructed = new RustRepresentationDynamicBox(5);
		var casted:Dynamic = cast 6;
		return if (flag) 7 else 8;
	}

	static function main():Void {}
}

typedef RustRepresentationBorrowedHolder = {
	@:optional var value:Null<rust.Ref<Int>>;
}

// Kept unused by ordinary source lowering: the compile-time contract below constructs one
// instantiated node directly and proves the analyzer terminates conservatively when the same
// typedef is revisited with a larger type argument.
typedef RustRepresentationParameterGrowing<T> = Array<RustRepresentationParameterGrowing<Array<T>>>;

class RustRepresentationAnonymousPair<A, B> {
	public function new() {}
}

class RustRepresentationFixtureNode {
	public function new() {}
}

class RustRepresentationDynamicBox {
	public function new(value:Dynamic) {}
}

interface RustRepresentationFixtureContract {}

class RustRepresentationFixtureImplementation implements RustRepresentationFixtureContract {
	public function new() {}
}

enum RustRepresentationFixtureChoice {
	First;
	Payload(value:Dynamic);
}

class RustConstructorAnalysisFixture {
	static var escaped:rust.Ref<Int>;
	static var escapedClosure:Void->rust.Ref<Int>;

	public function new(borrowed:rust.Ref<Int>) {
		var alias = borrowed;
		escaped = alias;
		escapedClosure = () -> alias;
		var cwd = Sys.getCwd();
		var reflected = Reflect.field({value: 1}, "value");
		try {
			if (cwd.length == -1 || reflected == null)
				throw "constructor-only";
		} catch (_:String) {}
	}
}
