enum SampleFlavor {
	Vanilla;
}

class SampleBox {
	public var value:Int;

	public function new(value:Int) {
		this.value = value;
	}
}

class Main {
	/**
		Exercises framework-owned dynamic construction without making it an application API.

		Why
		- Application-authored `Type.createEnum` and `Type.createEmptyInstance` calls are rejected at
		  compile time, but upstream `haxe.Unserializer` necessarily retains those generic branches.
		- Accepted application code that reaches such a framework branch must receive a catchable Haxe
		  exception; a Rust `todo!()`, process panic, null sentinel, or silent partial value is forbidden.

		What
		- Accepts canonical serialized payloads produced by the Haxe 4.3.7 interpreter and asks the
		  upstream framework to deserialize them.
		- Reports only whether the expected operation-specific Haxe exception was caught.

		How
		- Serialized strings are protocol input and therefore a legitimate string boundary. `Dynamic`
		  appears only at the exception boundary required by Haxe's catch-all contract.
	**/
	static function expectFrameworkFailure(label:String, encoded:String, expectedOperation:String):Void {
		var outcome = "not_caught";
		try {
			haxe.Unserializer.run(encoded);
		} catch (error:Dynamic) {
			var message = Std.string(error);
			outcome = message.indexOf(expectedOperation) >= 0 ? "caught" : "wrong_error";
		}
		Sys.println(label + "=" + outcome);
	}

	static function main():Void {
		#if reflection_oracle
		Sys.println(haxe.Serializer.run(SampleFlavor.Vanilla));
		Sys.println(haxe.Serializer.run(new SampleBox(7)));
		#else
		var payloads = Sys.args();
		if (payloads.length != 2)
			throw "expected enum and class serialization payloads";
		expectFrameworkFailure("enum", payloads[0], "Type.createEnum");
		expectFrameworkFailure("class", payloads[1], "Type.createEmptyInstance");
		#end
	}
}
