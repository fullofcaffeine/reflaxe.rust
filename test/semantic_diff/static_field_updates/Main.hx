private class StaticState {
	public static var count:Int = 10;
	public static var label:String = "state";
}

class Main {
	static var rhsCalls = 0;
	static var localCount = 2;

	static function rhs(value:Int):Int {
		rhsCalls = rhsCalls + 1;
		return value;
	}

	static function main() {
		Sys.println("add-result=" + (StaticState.count += rhs(5)));
		Sys.println("add-value=" + StaticState.count);
		Sys.println("add-calls=" + rhsCalls);
		Sys.println("post-result=" + StaticState.count++);
		Sys.println("post-value=" + StaticState.count);
		Sys.println("pre-result=" + ++StaticState.count);
		Sys.println("pre-value=" + StaticState.count);
		Sys.println("post-dec-result=" + StaticState.count--);
		Sys.println("post-dec-value=" + StaticState.count);
		Sys.println("pre-dec-result=" + --StaticState.count);
		Sys.println("pre-dec-value=" + StaticState.count);
		Sys.println("sub-result=" + (StaticState.count -= 3));
		Sys.println("sub-value=" + StaticState.count);
		Sys.println("label-result=" + (StaticState.label += ":updated"));
		Sys.println("label-value=" + StaticState.label);
		Sys.println("main-add-result=" + (localCount += 4));
		Sys.println("main-post-result=" + localCount++);
		Sys.println("main-value=" + localCount);
	}
}
