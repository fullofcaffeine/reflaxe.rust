interface Service {
	function name():String;
}

class Impl implements Service {
	public function new() {}

	public function name():String {
		return "impl";
	}
}

class Main {
	static function missing():Service {
		return null;
	}

	static function describe(service:Service):String {
		return "service:" + service.name();
	}

	static function main():Void {
		Sys.println(describe(new Impl()));
	}
}
