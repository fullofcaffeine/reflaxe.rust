package sys;

/**
	`sys.FileSystem` (Rust target implementation)

	Why
	- The upstream Haxe std declares `sys.FileSystem` as `extern`, so the target must provide a
	  concrete implementation.
	- For production use, common failures (permission denied, missing path, etc.) must be catchable
	  Haxe exceptions (not Rust panics from `unwrap()`).

	What
	- Implements the full upstream API surface:
	  `exists`, `rename`, `stat`, `fullPath`, `absolutePath`,
	  `isDirectory`, `createDirectory`, `deleteFile`, `deleteDirectory`, `readDirectory`.

	How
	- Implemented via internal `__rust__` injections (framework-only).
	- Errors throw via `hxrt::exception::throw(hxrt::dynamic::from(String))` so they can be caught.
	- `stat()` returns a `sys.FileStat` anonymous object.
**/
class FileSystem {
	public static function exists(path:String):Bool {
		return untyped __rust__("std::path::Path::new({0}.as_str()).exists()", path);
	}

	public static function rename(path:String, newPath:String):Void {
		untyped __rust__("match std::fs::rename({0}.as_str(), {1}.as_str()) {
				Ok(()) => (),
				Err(e) => hxrt::exception::throw(hxrt::dynamic::from(format!(\"{}\", e))),
			}", path, newPath);
	}

	public static function stat(path:String):FileStat {
		var atMs:Float = untyped __rust__("{
				use std::time::SystemTime;
				let md = match std::fs::metadata({0}.as_str()) {
					Ok(m) => m,
					Err(e) => hxrt::exception::throw(hxrt::dynamic::from(format!(\"{}\", e))),
				};
				let t = match md.accessed().or_else(|_| md.modified()) {
					Ok(t) => t,
					Err(e) => hxrt::exception::throw(hxrt::dynamic::from(format!(\"{}\", e))),
				};
				let dur = match t.duration_since(SystemTime::UNIX_EPOCH) {
					Ok(d) => d,
					Err(_) => std::time::Duration::from_secs(0),
				};
				dur.as_millis() as f64
			}", path);
		var mtMs:Float = untyped __rust__("{
				use std::time::SystemTime;
				let md = match std::fs::metadata({0}.as_str()) {
					Ok(m) => m,
					Err(e) => hxrt::exception::throw(hxrt::dynamic::from(format!(\"{}\", e))),
				};
				let t = match md.modified() {
					Ok(t) => t,
					Err(e) => hxrt::exception::throw(hxrt::dynamic::from(format!(\"{}\", e))),
				};
				let dur = match t.duration_since(SystemTime::UNIX_EPOCH) {
					Ok(d) => d,
					Err(_) => std::time::Duration::from_secs(0),
				};
				dur.as_millis() as f64
			}", path);
		var ctMs:Float = untyped __rust__("{
				use std::time::SystemTime;
				let md = match std::fs::metadata({0}.as_str()) {
					Ok(m) => m,
					Err(e) => hxrt::exception::throw(hxrt::dynamic::from(format!(\"{}\", e))),
				};
				let t = match md.created().or_else(|_| md.modified()) {
					Ok(t) => t,
					Err(e) => hxrt::exception::throw(hxrt::dynamic::from(format!(\"{}\", e))),
				};
				let dur = match t.duration_since(SystemTime::UNIX_EPOCH) {
					Ok(d) => d,
					Err(_) => std::time::Duration::from_secs(0),
				};
				dur.as_millis() as f64
			}", path);

		var size:Int = untyped __rust__("{
				let md = match std::fs::metadata({0}.as_str()) {
					Ok(m) => m,
					Err(e) => hxrt::exception::throw(hxrt::dynamic::from(format!(\"{}\", e))),
				};
				(md.len() as i64) as i32
			}", path);

		// Unix-only extended metadata; best-effort elsewhere.
		var gid:Int = untyped __rust__("{
				#[cfg(unix)]
				{
					use std::os::unix::fs::MetadataExt;
					let md = match std::fs::metadata({0}.as_str()) {
						Ok(m) => m,
						Err(e) => hxrt::exception::throw(hxrt::dynamic::from(format!(\"{}\", e))),
					};
					md.gid() as i32
				}
				#[cfg(not(unix))]
				{ 0i32 }
			}", path);
		var uid:Int = untyped __rust__("{
				#[cfg(unix)]
				{
					use std::os::unix::fs::MetadataExt;
					let md = match std::fs::metadata({0}.as_str()) {
						Ok(m) => m,
						Err(e) => hxrt::exception::throw(hxrt::dynamic::from(format!(\"{}\", e))),
					};
					md.uid() as i32
				}
				#[cfg(not(unix))]
				{ 0i32 }
			}", path);
		var dev:Int = untyped __rust__("{
				#[cfg(unix)]
				{
					use std::os::unix::fs::MetadataExt;
					let md = match std::fs::metadata({0}.as_str()) {
						Ok(m) => m,
						Err(e) => hxrt::exception::throw(hxrt::dynamic::from(format!(\"{}\", e))),
					};
					(md.dev() as i64) as i32
				}
				#[cfg(not(unix))]
				{ 0i32 }
			}", path);
		var ino:Int = untyped __rust__("{
				#[cfg(unix)]
				{
					use std::os::unix::fs::MetadataExt;
					let md = match std::fs::metadata({0}.as_str()) {
						Ok(m) => m,
						Err(e) => hxrt::exception::throw(hxrt::dynamic::from(format!(\"{}\", e))),
					};
					(md.ino() as i64) as i32
				}
				#[cfg(not(unix))]
				{ 0i32 }
			}", path);
		var nlink:Int = untyped __rust__("{
				#[cfg(unix)]
				{
					use std::os::unix::fs::MetadataExt;
					let md = match std::fs::metadata({0}.as_str()) {
						Ok(m) => m,
						Err(e) => hxrt::exception::throw(hxrt::dynamic::from(format!(\"{}\", e))),
					};
					(md.nlink() as i64) as i32
				}
				#[cfg(not(unix))]
				{ 0i32 }
			}", path);
		var rdev:Int = untyped __rust__("{
				#[cfg(unix)]
				{
					use std::os::unix::fs::MetadataExt;
					let md = match std::fs::metadata({0}.as_str()) {
						Ok(m) => m,
						Err(e) => hxrt::exception::throw(hxrt::dynamic::from(format!(\"{}\", e))),
					};
					(md.rdev() as i64) as i32
				}
				#[cfg(not(unix))]
				{ 0i32 }
			}", path);
		var mode:Int = untyped __rust__("{
				#[cfg(unix)]
				{
					use std::os::unix::fs::MetadataExt;
					let md = match std::fs::metadata({0}.as_str()) {
						Ok(m) => m,
						Err(e) => hxrt::exception::throw(hxrt::dynamic::from(format!(\"{}\", e))),
					};
					(md.mode() as i64) as i32
				}
				#[cfg(not(unix))]
				{ 0i32 }
			}", path);

		return {
			gid: gid,
			uid: uid,
			atime: Date.fromTime(atMs),
			mtime: Date.fromTime(mtMs),
			ctime: Date.fromTime(ctMs),
			size: size,
			dev: dev,
			ino: ino,
			nlink: nlink,
			rdev: rdev,
			mode: mode,
		};
	}

	public static function fullPath(relPath:String):String {
		return untyped __rust__("match std::fs::canonicalize({0}.as_str()) {
				Ok(p) => p.to_string_lossy().to_string(),
				Err(e) => hxrt::exception::throw(hxrt::dynamic::from(format!(\"{}\", e))),
			}", relPath);
	}

	public static function absolutePath(relPath:String):String {
		return untyped __rust__("{
				let p = std::path::Path::new({0}.as_str());
				let out = if p.is_absolute() {
					p.to_path_buf()
				} else {
					let cwd = match std::env::current_dir() {
						Ok(d) => d,
						Err(e) => hxrt::exception::throw(hxrt::dynamic::from(format!(\"{}\", e))),
					};
					cwd.join(p)
				};
				out.to_string_lossy().to_string()
			}", relPath);
	}

	public static function isDirectory(path:String):Bool {
		return untyped __rust__("match std::fs::metadata({0}.as_str()) {
				Ok(m) => m.is_dir(),
				Err(e) => hxrt::exception::throw(hxrt::dynamic::from(format!(\"{}\", e))),
			}", path);
	}

	public static function createDirectory(path:String):Void {
		untyped __rust__("match std::fs::create_dir_all({0}.as_str()) {
				Ok(()) => (),
				Err(e) => hxrt::exception::throw(hxrt::dynamic::from(format!(\"{}\", e))),
			}", path);
	}

	public static function deleteFile(path:String):Void {
		untyped __rust__("match std::fs::remove_file({0}.as_str()) {
				Ok(()) => (),
				Err(e) => hxrt::exception::throw(hxrt::dynamic::from(format!(\"{}\", e))),
			}", path);
	}

	public static function deleteDirectory(path:String):Void {
		untyped __rust__("match std::fs::remove_dir({0}.as_str()) {
				Ok(()) => (),
				Err(e) => hxrt::exception::throw(hxrt::dynamic::from(format!(\"{}\", e))),
			}", path);
	}

	public static function readDirectory(path:String):Array<String> {
		#if rust_string_nullable
		return untyped __rust__("{
				let mut out: Vec<String> = Vec::new();
				let rd = match std::fs::read_dir({0}.as_str()) {
					Ok(r) => r,
					Err(e) => hxrt::exception::throw(hxrt::dynamic::from(format!(\"{}\", e))),
				};
				for entry in rd {
					let e = match entry {
						Ok(e) => e,
						Err(e) => hxrt::exception::throw(hxrt::dynamic::from(format!(\"{}\", e))),
					};
					let name = e.file_name().to_string_lossy().to_string();
					out.push(name);
				}
				hxrt::array::Array::<hxrt::string::HxString>::from_vec(out.into_iter().map(hxrt::string::HxString::from).collect::<Vec<hxrt::string::HxString>>())
			}", path);
		#else
		return untyped __rust__("{
				let mut out: Vec<String> = Vec::new();
				let rd = match std::fs::read_dir({0}.as_str()) {
					Ok(r) => r,
					Err(e) => hxrt::exception::throw(hxrt::dynamic::from(format!(\"{}\", e))),
				};
				for entry in rd {
					let e = match entry {
						Ok(e) => e,
						Err(e) => hxrt::exception::throw(hxrt::dynamic::from(format!(\"{}\", e))),
					};
					let name = e.file_name().to_string_lossy().to_string();
					out.push(name);
				}
				hxrt::array::Array::<String>::from_vec(out)
			}", path);
		#end
	}
}
