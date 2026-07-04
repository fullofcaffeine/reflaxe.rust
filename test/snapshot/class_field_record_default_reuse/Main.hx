typedef ChildFields = {
	var name:String;
}

class Child {
	public var name:String;

	public function new(fields:ChildFields) {
		this.name = fields.name;
	}
}

typedef ParentFields = {
	var child:Child;
}

class Parent {
	public var child:Child;

	public function new(fields:ParentFields) {
		var provided = fields.child;
		this.child = provided;
	}
}

class ParentWithDefaultChild {
	public var child:Child;

	public function new() {}
}

class Main {
	static function main():Void {
		var parent = new Parent({
			child: new Child({name: "ready"})
		});
		trace(parent.child.name);

		var defaulted = new ParentWithDefaultChild();
		trace(defaulted.child == null);
	}
}
