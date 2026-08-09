private class BoundaryNode {
	public function new() {}
}

private enum BoundaryChoice {
	Selected;
}

private enum BoundaryStopChoice {
	First;
	Second;
}

private class BoundaryBox {
	public var initialized:Dynamic = 133133;

	public function new(value:Dynamic) {
		if (value == null) {}
	}
}

private class BoundaryDefaultBox {
	public var value:Dynamic;

	public function new(value:Dynamic = 172172) {
		this.value = value;
	}
}

private class BoundaryUnusedDefaultBox {
	public function new(value:Dynamic = 195195) {
		if (value == null) {}
	}
}

private class BoundaryAssignmentBase {
	public var inherited:Dynamic;

	public function new() {
		inherited = null;
	}
}

private class BoundaryAssignmentChild extends BoundaryAssignmentBase {
	public function new() {
		super();
	}

	public function assignInherited():Void {
		this.inherited = 151151;
	}
}

private class BoundaryReplayBase {
	static final nestedRepeated:Dynamic = 192192;

	public function new() {
		var constructorValue:Dynamic = 181181;
		var nestedValue:Dynamic = nestedRepeated;
		if (constructorValue == null || nestedValue == null) {}
	}
}

private class BoundaryReplayChild extends BoundaryReplayBase {
	public function new() {
		super();
	}
}

class Main {
	static var flag:Bool = false;
	static var selector:Int = 1;
	static var initialized:Dynamic = 131131;
	static var assigned:Dynamic;
	static final repeated:Dynamic = 191191;
	static final unusedRepeated:Dynamic = 193193;
	static var factoryField:Void->Dynamic = () -> 166166;

	static function consumeDynamic(value:Dynamic):Void if (value == null) {}
	static function consumeDefault(value:Dynamic = 171171):Void if (value == null) {}
	static function unusedDefault(value:Dynamic = 194194):Void if (value == null) {}
	static function consumeFactory(factory:Void->Dynamic):Dynamic return factory();
	static function returnFactory():Void->Dynamic return () -> 165165;

	static function concreteReturn():Dynamic {
		return 606060;
	}

	static function stopAfterEnum(choice:BoundaryStopChoice):Dynamic {
		switch choice {
			case First: return 201201;
			case Second: return 202202;
		}
		var unreachable:Dynamic = 203203;
		return unreachable;
	}

	static function stopAfterBool(value:Bool):Dynamic {
		switch value {
			case true: throw 204204;
			case false: throw 205205;
		}
		var unreachable:Dynamic = 206206;
		return unreachable;
	}

	static function stopBeforeImplicit(choice:BoundaryStopChoice):Dynamic {
		switch choice {
			case First: return 208208;
			case Second: return 209209;
		}
		207207;
	}

	static function exerciseImplicitBoxes(node:BoundaryNode):Void {
		trace(node);
		var rendered = Std.string(node);
		if (flag && rendered.length == -1)
			throw node;
	}

	static function main():Void {
		consumeDynamic(new BoundaryNode());
		exerciseImplicitBoxes(new BoundaryNode());
		consumeDynamic(BoundaryChoice.Selected);
		var boxed = new BoundaryBox(707070);
		var local:Dynamic = 808080;
		var localBeforeAssignment = local == null;
		local = 909090;
		var equal = local == 101101;
		var unequal = 102102 != local;
		assigned = 132132;
		var values:Array<Dynamic> = [];
		values[0] = 141141;
		var object:{value:Dynamic} = {value: null};
		object.value = 142142;
		var optionalForDynamic:Null<Bool> = null;
		var dynamicLiteral:{value:Dynamic} = {value: optionalForDynamic};
		var dynamicAssigned:{value:Dynamic} = {value: true};
		var dynamicAssignedBefore:Dynamic = dynamicAssigned.value;
		dynamicAssigned.value = optionalForDynamic;
		var inherited = new BoundaryAssignmentChild();
		inherited.assignInherited();
		consumeDefault();
		consumeDefault();
		var defaultBoxFirst = new BoundaryDefaultBox();
		var defaultBoxSecond = new BoundaryDefaultBox();
		var make:Void->Dynamic = () -> 161161;
		var made:Dynamic = make();
		var calledFactory:Dynamic = consumeFactory(() -> 162162);
		var factories:Array<Void->Dynamic> = [() -> 163163];
		var factoryRecord:{factory:Void->Dynamic} = {factory: () -> 164164};
		var factoryRecordBefore:Dynamic = factoryRecord.factory();
		factoryRecord.factory = () -> 169169;
		var returnedFactory = returnFactory();
		var reassignedFactory:Void->Dynamic = () -> 167167;
		var reassignedBefore:Dynamic = reassignedFactory();
		reassignedFactory = () -> 168168;
		var base = new BoundaryReplayBase();
		var child = new BoundaryReplayChild();
		var repeatedFirst:Dynamic = repeated;
		var repeatedSecond:Dynamic = repeated;
		CrossModuleBoundary.consume();
		CrossModuleBoundary.consume();
		var crossModuleFirst = new CrossModuleBoundary();
		var crossModuleSecond = new CrossModuleBoundary();
		var crossModuleRepeatedFirst:Dynamic = CrossModuleBoundary.repeated;
		var crossModuleRepeatedSecond:Dynamic = CrossModuleBoundary.repeated;
		var stopped:Dynamic = stopAfterEnum(flag ? First : Second);
		var stoppedImplicit:Dynamic = stopBeforeImplicit(flag ? First : Second);
		if (flag)
			stopAfterBool(flag);
		consumeDynamic(cast(new BoundaryNode(), BoundaryNode));
		consumeDynamic(if (flag) 111111 else 112112);
		consumeDynamic(switch (selector) { case 1: 121121; default: 122122; });
		var returned:Dynamic = concreteReturn();
		if (boxed == null || boxed.initialized == null || localBeforeAssignment || local == null || returned == null || initialized == null || assigned == null || values == null || object == null
			|| inherited == null || made == null || calledFactory == null || factories[0]() == null || factoryRecordBefore == null || factoryRecord.factory() == null
			|| returnedFactory() == null || reassignedBefore == null || reassignedFactory() == null || factoryField() == null || base == null || child == null || repeatedFirst == null || repeatedSecond == null
			|| crossModuleFirst.value == null || crossModuleSecond.value == null || crossModuleRepeatedFirst == null || crossModuleRepeatedSecond == null
			|| defaultBoxFirst.value == null || defaultBoxSecond.value == null || stopped == null || stoppedImplicit == null || equal && unequal) {}
		if (dynamicAssignedBefore == null || dynamicLiteral.value != null || dynamicAssigned.value != null)
			throw "dynamic-storage-carrier";
	}
}
