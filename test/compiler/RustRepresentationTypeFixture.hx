class RustRepresentationTypeFixture {
	static var scalar:Int;
	static var enumValue:RustRepresentationFixtureChoice;
	static var nativeOwned:rust.Vec<Int>;
	static var nativeOwnedDynamic:rust.Vec<Dynamic>;
	static var sharedIdentity:RustRepresentationFixtureNode;
	static var polymorphic:RustRepresentationFixtureContract;
	static var borrowed:rust.Ref<Int>;
	static var nullableBorrowed:Null<rust.Ref<Int>>;
	static var nativeHandle:rust.net.TcpStream;
	static var dynamicValue:Dynamic;
	static var stringValue:String;
	static var arrayValue:Array<Int>;
	static var anonymousValue:{value:Int};
	static var functionValue:Int->String;
	static var iteratorValue:Iterator<Int>;
	static var nullableValue:Null<Int>;
	static var mapValue:Map<String, String>;
	static function consumeDynamic(value:Dynamic):Void {}

	static function main():Void {}
}

class RustRepresentationFixtureNode {
	public function new() {}
}

interface RustRepresentationFixtureContract {}

class RustRepresentationFixtureImplementation implements RustRepresentationFixtureContract {
	public function new() {}
}

enum RustRepresentationFixtureChoice {
	First;
	Payload(value:Dynamic);
}
