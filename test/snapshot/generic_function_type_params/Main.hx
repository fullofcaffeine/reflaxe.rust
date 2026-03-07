import reflaxe.std.Option;

class Main {
	static function optionMap<T, U>(value:Option<T>, f:T->U):Option<U> {
		return switch value {
			case Some(v): Some(f(v));
			case None: None;
		};
	}

	static function render<T>(value:Option<T>):String {
		return switch value {
			case Some(_): "some";
			case None: "none";
		};
	}

	static function main() {
		Sys.println(render(optionMap(Some(1), v -> v + 1)));
		Sys.println(render(optionMap(None, v -> v + 1)));
	}
}
