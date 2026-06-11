class Main {
	static function main():Void {
		var value = "alpha/beta/alpha";
		Sys.println(value.lastIndexOf("alpha"));
		Sys.println(value.lastIndexOf("alpha", 7));
		Sys.println(value.lastIndexOf("/"));
		Sys.println(value.lastIndexOf("missing"));
	}
}
