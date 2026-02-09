import sys.FileSystem;
import sys.io.File;
import sys.io.FileSeek;

class Main {
	static function main() {
		var path = "reflaxe_rust_sys_file_io_tmp.txt";
		var path2 = "reflaxe_rust_sys_file_io_tmp2.txt";

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

		// FileSystem extras (parity checks)
		FileSystem.rename(path, path2);
		if (FileSystem.exists(path)) throw "rename failed (old path still exists)";
		if (!FileSystem.exists(path2)) throw "rename failed (new path missing)";

		if (FileSystem.isDirectory(path2)) throw "expected file, got directory";

		var abs = FileSystem.absolutePath(path2);
		if (abs == "") throw "absolutePath returned empty";

		var full = FileSystem.fullPath(path2);
		if (full == "") throw "fullPath returned empty";

		var st = FileSystem.stat(path2);
		if (st.size <= 0) throw "stat size should be > 0";
		if (st.mtime.getTime() < 0.0) throw "stat mtime should be >= 0";

		var threw = false;
		try {
			FileSystem.isDirectory("reflaxe_rust_missing_dir_hopefully");
		} catch (_: Dynamic) {
			threw = true;
		}
		if (!threw) throw "isDirectory should throw on missing path";

		if (FileSystem.exists(path2)) FileSystem.deleteFile(path2);
	}
}
