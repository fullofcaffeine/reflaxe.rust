class PersonGreeter implements Greeter {
	public var name:String;

	public function new(name:String) {
		this.name = name;
	}

	public function greet():String {
		return "hello " + name;
	}
}

class GreeterRunner {
	public static function run(greeter:Greeter):String {
		return greeter.greet();
	}
}

class Main {
	static function main():Void {
		var greeter:Greeter = new PersonGreeter("metal");
		Sys.println(GreeterRunner.run(greeter));
	}
}
