class Payload<T> {
	public var value:T;

	public function new(value:T) {
		this.value = value;
	}
}

class Helpers {
	public static function make<T>(value:T):Payload<T> {
		return new Payload(value);
	}

	public static function read<T>(payload:Payload<T>):T {
		return payload.value;
	}
}

class Main {
	static function main() {
		var payload = Helpers.make("ok");
		Sys.println(Helpers.read(payload));
	}
}
