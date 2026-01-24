using rust.OptionTools;

import rust.Option;

class Main {
	static function main() {
		var o: Option<Int> = Some(1);
		var v = o.unwrapOr(0);
		trace(v);
	}
}

