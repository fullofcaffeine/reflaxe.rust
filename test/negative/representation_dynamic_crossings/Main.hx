private class BoundaryNode {
	public function new() {}
}

private enum BoundaryChoice {
	Selected;
}

private class BoundaryBox {
	public function new(value:Dynamic) {}
}

class Main {
	static var flag:Bool = false;
	static var selector:Int = 1;

	static function consumeDynamic(value:Dynamic):Void {}

	static function concreteReturn():Dynamic {
		return 606060;
	}

	static function main():Void {
		consumeDynamic(new BoundaryNode());
		consumeDynamic(BoundaryChoice.Selected);
		var boxed = new BoundaryBox(707070);
		var local:Dynamic = 808080;
		local = 909090;
		consumeDynamic(cast(new BoundaryNode(), BoundaryNode));
		consumeDynamic(if (flag) 111111 else 112112);
		consumeDynamic(switch (selector) { case 1: 121121; default: 122122; });
		var returned:Dynamic = concreteReturn();
		if (boxed == null || local == null || returned == null) {}
	}
}
