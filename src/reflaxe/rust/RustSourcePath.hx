package reflaxe.rust;

import haxe.io.Path;

/**
	Validates stable source identities shared by generated diagnostic artifacts.

	Why
	- Source-map and planner reports must never serialize machine-local absolute paths or traversal.
	- Maintaining separate path rules would let one report accept a source identity another rejects.

	What
	- Accepts a non-empty relative path and returns its canonical slash-separated spelling.
	- Rejects absolute, drive-qualified, empty, dot, and dot-dot components before normalization.

	How
	- Inspect raw components first because `Path.normalize` would otherwise hide traversal.
	- Artifact codecs may safely store the returned value without a second path policy.
**/
class RustSourcePath {
	/**
		Returns one canonical report-safe relative path or fails immediately.

		Why / What / How
		- Validate raw slash-normalized components before `Path.normalize`, because normalization would
		  otherwise erase evidence of traversal. Error text deliberately does not echo a rejected local
		  path, preventing diagnostics from becoming a second privacy leak.
	**/
	public static function requireRelativePath(value:String, label:String):String {
		if (value == null || value.length == 0)
			throw '$label cannot be empty';
		var slashed = value.split("\\").join("/");
		if (Path.isAbsolute(slashed) || ~/^[A-Za-z]:/.match(slashed))
			throw '$label must be relative';
		if (~/[\x00-\x1f\x7f]/.match(slashed))
			throw '$label contains a control character';
		for (segment in slashed.split("/")) {
			if (segment.length == 0 || segment == "." || segment == "..")
				throw '$label contains an unsafe path segment';
		}
		return Path.normalize(slashed).split("\\").join("/");
	}
}
