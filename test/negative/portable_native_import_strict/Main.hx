import rust.Option;

class Main {
	static function main():Void {
		var value:Option<Int> = Some(1);
		switch (value) {
			case Some(v):
				Sys.println(v);
			case None:
				Sys.println("none");
		}
	}
}
