class Main {
	static function main():Void {
		var value:rust.Option<Int> = rust.Option.Some(7);
		switch (value) {
			case Some(v):
				Sys.println(v);
			case None:
				Sys.println("none");
		}
	}
}
