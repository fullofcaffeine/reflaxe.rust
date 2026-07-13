private class Payload {
	public var value:Int;

	public function new(value:Int) {
		this.value = value;
	}
}

class Main {
	static var order = "";
	static var intCalls = 0;
	static var nullIntCalls = 0;
	static var payloadCalls = 0;
	static var nullPayloadCalls = 0;

	static function intValue():Int {
		order = order + "i";
		intCalls = intCalls + 1;
		return 7;
	}

	static function nullIntValue():Null<Int> {
		order = order + "n";
		nullIntCalls = nullIntCalls + 1;
		return null;
	}

	static function payloadValue(value:Payload):Payload {
		order = order + "p";
		payloadCalls = payloadCalls + 1;
		return value;
	}

	static function nullPayloadValue():Null<Payload> {
		order = order + "z";
		nullPayloadCalls = nullPayloadCalls + 1;
		return null;
	}

	static function payloadAt(values:Array<Null<Payload>>, index:Int):Null<Payload> {
		return values[index];
	}

	static function main() {
		var ints:Array<Null<Int>> = [intValue(), nullIntValue(), 9];
		Sys.println("int-0=" + ints[0]);
		Sys.println("int-1-null=" + (ints[1] == null));
		Sys.println("int-2=" + ints[2]);
		Sys.println("int-oob-null=" + (ints[9] == null));

		var shared = new Payload(10);
		var payloads:Array<Null<Payload>> = [payloadValue(shared), nullPayloadValue(), shared];
		shared.value = 12;
		Sys.println("payload-0=" + payloadAt(payloads, 0).value);
		Sys.println("payload-1-null=" + (payloadAt(payloads, 1) == null));
		Sys.println("payload-2=" + payloadAt(payloads, 2).value);

		Sys.println("order=" + order);
		Sys.println("int-calls=" + intCalls);
		Sys.println("null-int-calls=" + nullIntCalls);
		Sys.println("payload-calls=" + payloadCalls);
		Sys.println("null-payload-calls=" + nullPayloadCalls);
	}
}
