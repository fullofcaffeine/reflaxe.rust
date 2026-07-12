private class CounterBase {
	public var count:Int;
	public var label:String;

	public function new(count:Int, label:String) {
		this.count = count;
		this.label = label;
	}
}

private class CounterChild extends CounterBase {
	public function new(count:Int, label:String) {
		super(count, label);
	}
}

private class PlainCounter {
	public var count:Int;

	public function new(count:Int) {
		this.count = count;
	}
}

class Main {
	static var receiverCalls = 0;
	static var rhsCalls = 0;

	static function receiver(value:CounterBase):CounterBase {
		receiverCalls = receiverCalls + 1;
		return value;
	}

	static function rhs(value:Int):Int {
		rhsCalls = rhsCalls + 1;
		return value;
	}

	static function main() {
		var polymorphic:CounterBase = new CounterChild(10, "child");
		Sys.println("add-result=" + (receiver(polymorphic).count += rhs(5)));
		Sys.println("add-value=" + polymorphic.count);
		Sys.println("add-calls=" + receiverCalls + ":" + rhsCalls);
		Sys.println("post-result=" + receiver(polymorphic).count++);
		Sys.println("post-value=" + polymorphic.count);
		Sys.println("post-calls=" + receiverCalls);
		Sys.println("pre-result=" + ++receiver(polymorphic).count);
		Sys.println("pre-value=" + polymorphic.count);
		Sys.println("pre-calls=" + receiverCalls);
		Sys.println("post-dec-result=" + polymorphic.count--);
		Sys.println("post-dec-value=" + polymorphic.count);
		Sys.println("pre-dec-result=" + --polymorphic.count);
		Sys.println("pre-dec-value=" + polymorphic.count);
		Sys.println("sub-result=" + (polymorphic.count -= 3));
		Sys.println("sub-value=" + polymorphic.count);
		Sys.println("label-result=" + (polymorphic.label += ":updated"));
		Sys.println("label-value=" + polymorphic.label);

		var concrete = new PlainCounter(4);
		Sys.println("direct-result=" + (concrete.count *= 2));
		Sys.println("direct-value=" + concrete.count);
	}
}
