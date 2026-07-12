private class StaticProperties {
	static var backing = 10;
	static var backingLabel = "state";
	public static var readCalls = 0;
	public static var writeCalls = 0;
	public static var value(get, set):Int;
	public static var label(get, set):String;

	static function get_value():Int {
		readCalls = readCalls + 1;
		return backing;
	}

	static function set_value(next:Int):Int {
		writeCalls = writeCalls + 1;
		backing = next * 2;
		return backing;
	}

	static function get_label():String {
		readCalls = readCalls + 1;
		return backingLabel;
	}

	static function set_label(next:String):String {
		writeCalls = writeCalls + 1;
		backingLabel = next + "!";
		return backingLabel;
	}
}

class Main {
	static function main() {
		Sys.println("read=" + StaticProperties.value);
		Sys.println("assign-result=" + (StaticProperties.value = 3));
		Sys.println("assign-value=" + StaticProperties.value);
		Sys.println("add-result=" + (StaticProperties.value += 2));
		Sys.println("add-value=" + StaticProperties.value);
		Sys.println("post-result=" + StaticProperties.value++);
		Sys.println("post-value=" + StaticProperties.value);
		Sys.println("pre-result=" + ++StaticProperties.value);
		Sys.println("pre-value=" + StaticProperties.value);
		Sys.println("label-result=" + (StaticProperties.label += ":updated"));
		Sys.println("label-value=" + StaticProperties.label);
		Sys.println("read-calls=" + StaticProperties.readCalls);
		Sys.println("write-calls=" + StaticProperties.writeCalls);
	}
}
