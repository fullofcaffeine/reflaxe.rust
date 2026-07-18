class Main {
	static function main():Void {
		var first = Type.getClassName(Main);
		var second = Type.getClassName(Main);
		if (first == second && first.length == -1) {}
	}
}
