private class GenericBox<T> {
	public final value:T;

	public function new(value:T) {
		this.value = value;
	}

	public function inheritedValue():T {
		return value;
	}

	public function echo(value:T):T {
		return value;
	}
}

private class StringBox extends GenericBox<String> {
	public function new(value:String) {
		super(value);
	}

	override public function echo(value:String):String {
		return "string:" + value;
	}
}

private class ArrayBox<T> extends GenericBox<Array<T>> {
	public function new(value:Array<T>) {
		super(value);
	}
}

private class StringArrayBox extends ArrayBox<String> {
	public function new(value:Array<String>) {
		super(value);
	}
}

class Main {
	static function main() {
		var concrete = new StringBox("stored");
		Sys.println("field=" + concrete.value);
		Sys.println("inherited=" + concrete.inheritedValue());
		Sys.println("override=" + concrete.echo("direct"));

		var base:GenericBox<String> = concrete;
		Sys.println("base-inherited=" + base.inheritedValue());
		Sys.println("base-override=" + base.echo("dispatch"));

		var nested = new StringArrayBox(["one", "two"]);
		Sys.println("nested=" + nested.inheritedValue().join(","));
		var nestedBase:GenericBox<Array<String>> = nested;
		Sys.println("nested-base=" + nestedBase.value.join("+"));
	}
}
