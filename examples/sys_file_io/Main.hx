import sys.FileSystem;
import sys.io.File;
import sys.io.FileSeek;

class Main {
	static function main() {
		var path = "reflaxe_rust_sys_file_io_tmp.txt";

		File.saveContent(path, "hello");
		var out = File.append(path);
		out.writeString(" world");
		out.close();

		var update = File.update(path);
		update.seek(0, FileSeek.SeekBegin);
		update.writeString("HELLO");
		update.close();

		var input = File.read(path);
		var content = input.readAll().toString();
		input.close();

		Sys.println(content);

		if (FileSystem.exists(path)) {
			FileSystem.deleteFile(path);
		}
	}
}

