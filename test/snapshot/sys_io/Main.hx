import sys.FileSystem;
import sys.io.File;
import haxe.io.Bytes;

class Main {
	static function main(): Void {
		trace("--- args ---");
		trace(Sys.args().length);

		trace("--- file content ---");
		var path = "tmp_sys_io.txt";
		File.saveContent(path, "hello");
		trace(File.getContent(path));
		trace(FileSystem.exists(path));
		FileSystem.deleteFile(path);
		trace(FileSystem.exists(path));

		trace("--- file bytes ---");
		var bin = "tmp_sys_io.bin";
		var bytes = Bytes.ofString("ABC");
		File.saveBytes(bin, bytes);
		var bytes2 = File.getBytes(bin);
		trace(bytes2.toString());
		FileSystem.deleteFile(bin);

		trace("--- dir listing ---");
		var dir = "tmp_sys_dir";
		FileSystem.createDirectory(dir);
		File.saveContent(dir + "/a.txt", "a");
		File.saveContent(dir + "/b.txt", "b");
		var entries = FileSystem.readDirectory(dir);

		var foundA = false;
		var foundB = false;
		var foundDot = false;
		var foundDotDot = false;
		for (e in entries) {
			if (e == "a.txt") foundA = true;
			if (e == "b.txt") foundB = true;
			if (e == ".") foundDot = true;
			if (e == "..") foundDotDot = true;
		}

		trace(foundA);
		trace(foundB);
		trace(foundDot);
		trace(foundDotDot);

		FileSystem.deleteFile(dir + "/a.txt");
		FileSystem.deleteFile(dir + "/b.txt");
		FileSystem.deleteDirectory(dir);
		trace(FileSystem.exists(dir));
	}
}

