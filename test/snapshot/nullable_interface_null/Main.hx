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
	static function describe(service:Null<Service>):String {
		if (service == null) {
			return "none";
		}
		return "service:" + service.name();
	}

	static function main():Void {
		var missing:Null<Service> = null;
		Sys.println(describe(missing));
		Sys.println(describe(new Impl()));
	}
}
