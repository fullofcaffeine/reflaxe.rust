private typedef CounterRecord = {
	var count:Int;
}

private class ConcreteState {
	public var count:Int;
	public var label:String;

	public function new(count:Int, label:String) {
		this.count = count;
		this.label = label;
	}

	public function mutateCount():Int {
		count = 100;
		return 5;
	}

	public function mutateLabel():String {
		label = "rhs";
		return ":tail";
	}
}

private class BaseState {
	public var count:Int;
	public var label:String;

	public function new(count:Int, label:String) {
		this.count = count;
		this.label = label;
	}
}

private class ChildState extends BaseState {
	public function new(count:Int, label:String) {
		super(count, label);
	}
}

private class AccessorState {
	var backingCount:Int;
	var backingLabel:String;
	public var count(get, set):Int;
	public var label(get, set):String;

	public function new(count:Int, label:String) {
		backingCount = count;
		backingLabel = label;
	}

	function get_count():Int {
		return backingCount;
	}

	function set_count(value:Int):Int {
		backingCount = value;
		return value;
	}

	function get_label():String {
		return backingLabel;
	}

	function set_label(value:String):String {
		backingLabel = value;
		return value;
	}

	public function mutateCount():Int {
		backingCount = 100;
		return 5;
	}

	public function mutateLabel():String {
		backingLabel = "rhs";
		return ":tail";
	}
}

private class StaticState {
	public static var count:Int = 10;
	public static var label:String = "static";

	public static function mutateCount():Int {
		count = 100;
		return 5;
	}

	public static function mutateLabel():String {
		label = "rhs";
		return ":tail";
	}
}

private class StaticAccessorState {
	static var backingCount:Int = 10;
	static var backingLabel:String = "accessor";
	public static var count(get, set):Int;
	public static var label(get, set):String;

	static function get_count():Int {
		return backingCount;
	}

	static function set_count(value:Int):Int {
		backingCount = value;
		return value;
	}

	static function get_label():String {
		return backingLabel;
	}

	static function set_label(value:String):String {
		backingLabel = value;
		return value;
	}

	public static function mutateCount():Int {
		backingCount = 100;
		return 5;
	}

	public static function mutateLabel():String {
		backingLabel = "rhs";
		return ":tail";
	}
}

class Main {
	static var concreteReceiverCalls = 0;
	static var baseReceiverCalls = 0;
	static var accessorReceiverCalls = 0;
	static var recordReceiverCalls = 0;

	static function concreteReceiver(value:ConcreteState):ConcreteState {
		concreteReceiverCalls = concreteReceiverCalls + 1;
		return value;
	}

	static function baseReceiver(value:BaseState):BaseState {
		baseReceiverCalls = baseReceiverCalls + 1;
		return value;
	}

	static function accessorReceiver(value:AccessorState):AccessorState {
		accessorReceiverCalls = accessorReceiverCalls + 1;
		return value;
	}

	static function recordReceiver(value:CounterRecord):CounterRecord {
		recordReceiverCalls = recordReceiverCalls + 1;
		return value;
	}

	static function mutateBaseCount(value:BaseState):Int {
		value.count = 100;
		return 5;
	}

	static function mutateBaseLabel(value:BaseState):String {
		value.label = "rhs";
		return ":tail";
	}

	static function mutateRecord(value:CounterRecord):Int {
		value.count = 100;
		return 5;
	}

	static function main() {
		var concrete = new ConcreteState(10, "concrete");
		Sys.println("concrete-count-result=" + (concreteReceiver(concrete).count += concrete.mutateCount()));
		Sys.println("concrete-count-value=" + concrete.count);
		Sys.println("concrete-label-result=" + (concreteReceiver(concrete).label += concrete.mutateLabel()));
		Sys.println("concrete-label-value=" + concrete.label);
		Sys.println("concrete-receiver-calls=" + concreteReceiverCalls);

		var polymorphic:BaseState = new ChildState(10, "polymorphic");
		Sys.println("polymorphic-count-result=" + (baseReceiver(polymorphic).count += mutateBaseCount(polymorphic)));
		Sys.println("polymorphic-count-value=" + polymorphic.count);
		Sys.println("polymorphic-label-result=" + (baseReceiver(polymorphic).label += mutateBaseLabel(polymorphic)));
		Sys.println("polymorphic-label-value=" + polymorphic.label);
		Sys.println("polymorphic-receiver-calls=" + baseReceiverCalls);

		var accessor = new AccessorState(10, "instance-accessor");
		Sys.println("accessor-count-result=" + (accessorReceiver(accessor).count += accessor.mutateCount()));
		Sys.println("accessor-count-value=" + accessor.count);
		Sys.println("accessor-label-result=" + (accessorReceiver(accessor).label += accessor.mutateLabel()));
		Sys.println("accessor-label-value=" + accessor.label);
		Sys.println("accessor-receiver-calls=" + accessorReceiverCalls);

		Sys.println("static-count-result=" + (StaticState.count += StaticState.mutateCount()));
		Sys.println("static-count-value=" + StaticState.count);
		Sys.println("static-label-result=" + (StaticState.label += StaticState.mutateLabel()));
		Sys.println("static-label-value=" + StaticState.label);

		Sys.println("static-accessor-count-result=" + (StaticAccessorState.count += StaticAccessorState.mutateCount()));
		Sys.println("static-accessor-count-value=" + StaticAccessorState.count);
		Sys.println("static-accessor-label-result=" + (StaticAccessorState.label += StaticAccessorState.mutateLabel()));
		Sys.println("static-accessor-label-value=" + StaticAccessorState.label);

		var record:CounterRecord = {count: 10};
		Sys.println("record-count-result=" + (recordReceiver(record).count += mutateRecord(record)));
		Sys.println("record-count-value=" + record.count);
		Sys.println("record-receiver-calls=" + recordReceiverCalls);
	}
}
