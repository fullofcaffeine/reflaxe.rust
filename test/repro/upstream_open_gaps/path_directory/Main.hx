import haxe.io.Path;

class Main {
	static function main():Void {
		Sys.println(Path.directory("alpha/beta/gamma.txt"));
		Sys.println(Path.directory("single.txt"));
		Sys.println(Path.directory("/root/file.txt"));
	}
}
