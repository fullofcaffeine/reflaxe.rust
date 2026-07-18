enum Token {
	Payload(value:Int);
}

class Main {
	static function main():Void {
		var immediate = Payload(41);
		#if capture_constructor
		var constructor = Payload;
		var captured = constructor(42);
		#end
	}
}
