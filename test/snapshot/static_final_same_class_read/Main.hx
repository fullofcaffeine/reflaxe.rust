class Main {
	static final LABEL:String = "static-final";
	static var counter:Int = 1;

	static function label():String {
		return LABEL;
	}

	static function next():Int {
		counter = counter + 1;
		return counter;
	}

	static function main():Void {
		Sys.println(label());
		Sys.println(next());
		Sys.println(next());
	}
}
