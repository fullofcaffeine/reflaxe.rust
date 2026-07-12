private interface ValueSource<T> {
	public function value():T;
	public function echo(value:T):T;
}

private interface NestedSource<T> extends ValueSource<Array<T>> {}

private class DirectStringSource implements ValueSource<String> {
	final stored:String;

	public function new(stored:String) {
		this.stored = stored;
	}

	public function value():String {
		return stored;
	}

	public function echo(value:String):String {
		return "direct:" + value;
	}
}

private class GenericSource<T> implements ValueSource<T> {
	final stored:T;

	public function new(stored:T) {
		this.stored = stored;
	}

	public function value():T {
		return stored;
	}

	public function echo(value:T):T {
		return value;
	}
}

private class InheritedStringSource extends GenericSource<String> {
	public function new(stored:String) {
		super(stored);
	}

	override public function echo(value:String):String {
		return "inherited:" + value;
	}
}

private class GenericNestedSource<T> extends GenericSource<Array<T>> {
	public function new(stored:Array<T>) {
		super(stored);
	}
}

private class InheritedNestedStringSource extends GenericNestedSource<String> {
	public function new(stored:Array<String>) {
		super(stored);
	}
}

private class NestedStringSource implements NestedSource<String> {
	final stored:Array<String>;

	public function new(stored:Array<String>) {
		this.stored = stored;
	}

	public function value():Array<String> {
		return stored;
	}

	public function echo(value:Array<String>):Array<String> {
		return value;
	}
}

class Main {
	static function main() {
		var direct:ValueSource<String> = new DirectStringSource("one");
		Sys.println(direct.value());
		Sys.println(direct.echo("two"));

		var inherited:ValueSource<String> = new InheritedStringSource("three");
		Sys.println(inherited.value());
		Sys.println(inherited.echo("four"));

		var nested:ValueSource<Array<String>> = new NestedStringSource(["five", "six"]);
		Sys.println(nested.value().join(","));
		Sys.println(nested.echo(["seven", "eight"]).join("+"));

		var inheritedNested:ValueSource<Array<String>> = new InheritedNestedStringSource(["nine", "ten"]);
		Sys.println(inheritedNested.value().join("/"));
		Sys.println(inheritedNested.echo(["eleven", "twelve"]).join("-"));
	}
}
