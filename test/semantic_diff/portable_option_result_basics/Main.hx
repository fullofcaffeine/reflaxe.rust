import reflaxe.std.Option;
import reflaxe.std.Result;

class Main {
	static function optionMap<T, U>(value:Option<T>, f:T->U):Option<U> {
		return switch value {
			case Some(v): Some(f(v));
			case None: None;
		};
	}

	static function optionAndThen<T, U>(value:Option<T>, f:T->Option<U>):Option<U> {
		return switch value {
			case Some(v): f(v);
			case None: None;
		};
	}

	static function optionOrElse<T>(value:Option<T>, fallback:Option<T>):Option<T> {
		return switch value {
			case Some(_): value;
			case None: fallback;
		};
	}

	static function optionUnwrapOr<T>(value:Option<T>, fallback:T):T {
		return switch value {
			case Some(v): v;
			case None: fallback;
		};
	}

	static function resultMap<T, U, E>(value:Result<T, E>, f:T->U):Result<U, E> {
		return switch value {
			case Ok(v): Ok(f(v));
			case Err(e): Err(e);
		};
	}

	static function resultMapErr<T, E, F>(value:Result<T, E>, f:E->F):Result<T, F> {
		return switch value {
			case Ok(v): Ok(v);
			case Err(e): Err(f(e));
		};
	}

	static function resultAndThen<T, U, E>(value:Result<T, E>, f:T->Result<U, E>):Result<U, E> {
		return switch value {
			case Ok(v): f(v);
			case Err(e): Err(e);
		};
	}

	static function renderOptionInt(value:Option<Int>):String {
		return switch value {
			case Some(v): "some:" + v;
			case None: "none";
		};
	}

	static function renderResultIntString(value:Result<Int, String>):String {
		return switch value {
			case Ok(v): "ok:" + v;
			case Err(e): "err:" + e;
		};
	}

	static function renderNested(value:Option<Result<Int, String>>):String {
		return switch value {
			case Some(Ok(v)): "some-ok:" + v;
			case Some(Err(e)): "some-err:" + e;
			case None: "none";
		};
	}

	static function main() {
		Sys.println("option.map.some=" + renderOptionInt(optionMap(Some(7), v -> v + 1)));
		Sys.println("option.map.none=" + renderOptionInt(optionMap(None, v -> v + 1)));
		Sys.println("option.andThen.some=" + renderOptionInt(optionAndThen(Some(7), v -> Some(v * 2))));
		Sys.println("option.andThen.none=" + renderOptionInt(optionAndThen(None, v -> Some(v * 2))));
		Sys.println("option.orElse.none=" + renderOptionInt(optionOrElse(None, Some(99))));
		Sys.println("option.unwrapOr.none=" + optionUnwrapOr(None, 42));

		Sys.println("result.map.ok=" + renderResultIntString(resultMap(Ok(5), v -> v + 10)));
		Sys.println("result.map.err=" + renderResultIntString(resultMap(Err("bad"), v -> v + 10)));
		Sys.println("result.mapErr.err=" + renderResultIntString(resultMapErr(Err("bad"), e -> e + "!")));
		Sys.println("result.andThen.ok=" + renderResultIntString(resultAndThen(Ok(5), v -> Ok(v * 3))));
		Sys.println("result.andThen.err=" + renderResultIntString(resultAndThen(Err("bad"), v -> Ok(v * 3))));

		Sys.println("nested.a=" + renderNested(Some(Ok(11))));
		Sys.println("nested.b=" + renderNested(Some(Err("oops"))));
		Sys.println("nested.c=" + renderNested(None));
	}
}
