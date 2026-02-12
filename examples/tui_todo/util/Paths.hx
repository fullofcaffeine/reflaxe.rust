package util;

import sys.FileSystem;

/**
	Filesystem paths for the example app.

	Why
	- This example is intended to behave like a real sys target app by default:
	  it persists data to a per-user config directory (not the repo).

	What
	- A small helper to compute:
	  - config directory
	  - the JSON data file path

	How
	- Test/dev override: `REFLAXE_RUST_TUI_CONFIG_DIR` (exact directory path)
	- Linux: `$XDG_CONFIG_HOME` or `~/.config`
	- macOS: `~/Library/Application Support`
	- Windows: `%APPDATA%` (fallback to `~\\AppData\\Roaming` best-effort)
**/
class Paths {
	static inline final APP_DIR = "reflaxe.rust";
	static inline final FILE_NAME = "tui_todo.json";

	public static function configDir(): String {
		var overrideDir = Sys.getEnv("REFLAXE_RUST_TUI_CONFIG_DIR");
		if (overrideDir != null && overrideDir.length > 0) return overrideDir;

		var sys = Sys.systemName();
		var home = Sys.getEnv("HOME");

		if (sys == "Windows") {
			var appdata = Sys.getEnv("APPDATA");
			if (appdata != null && appdata.length > 0) return join(appdata, APP_DIR);
			// Best-effort fallback.
			if (home != null && home.length > 0) return join(join(home, "AppData\\Roaming"), APP_DIR);
			return APP_DIR;
		}

		if (sys == "Mac") {
			if (home != null && home.length > 0) return join(join(join(home, "Library"), "Application Support"), APP_DIR);
			return APP_DIR;
		}

		// Linux / BSD-ish
		var xdg = Sys.getEnv("XDG_CONFIG_HOME");
		if (xdg != null && xdg.length > 0) return join(xdg, APP_DIR);
		if (home != null && home.length > 0) return join(join(home, ".config"), APP_DIR);
		return APP_DIR;
	}

	public static function dataFile(): String {
		return join(configDir(), FILE_NAME);
	}

	public static function ensureConfigDir(): Void {
		var dir = configDir();
		if (!FileSystem.exists(dir)) FileSystem.createDirectory(dir);
	}

	static function join(a: String, b: String): String {
		if (a.length == 0) return b;
		var sep = StringTools.endsWith(a, "/") || StringTools.endsWith(a, "\\") ? "" : "/";
		return a + sep + b;
	}
}
