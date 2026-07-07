import rust.PathBufTools;
import rust.Result;
import rust.fs.NativeFiles;

class Main {
	static function main() {
		var root = PathBufTools.fromString(".");
		var path = PathBufTools.join(root, "m43_native_file_probe.txt");

		switch (NativeFiles.writeString(path, "haxe-rust")) {
			case Ok(_):
			case Err(_):
				return;
		}

		switch (NativeFiles.readString(path)) {
			case Ok(text):
				if (text != "haxe-rust") {
					return;
				}
			case Err(_):
				return;
		}

		if (!NativeFiles.exists(path)) {
			return;
		}

		switch (NativeFiles.removeFile(path)) {
			case Ok(_):
			case Err(_):
		}
	}
}
