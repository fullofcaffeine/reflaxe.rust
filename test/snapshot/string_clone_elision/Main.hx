class Main {
	static function main(): Void {
		var s = "x";
		var t = s;
		s = "y";
		trace(t);
		trace(s);
	}
}
