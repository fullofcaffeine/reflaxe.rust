package supportcrate.helper;

import rust.Result;
import rust.Vec;

/**
	An owned directory capability used by the support-crate admission helper.

	Every child open is relative to this retained directory descriptor. The
	native facade rejects linked final components and returns only owned values.
**/
@:native("crate::support_crate_admission_fs::PinnedDirectory")
@:rustCargo({name: "rustix", version: "=1.1.4", defaultFeatures: false, features: ["std", "fs"]})
@:rustExtraSrc("support_crate_admission_fs.rs")
extern class PinnedDirectory {
	public function clone():PinnedDirectory;

	@:native("open_current")
	public static function openCurrent():Result<PinnedDirectory, AdmissionFsError>;

	@:native("open_root")
	public static function openRoot():Result<PinnedDirectory, AdmissionFsError>;

	@:native("open_directory")
	public function openDirectory(component:String):Result<PinnedDirectory, AdmissionFsError>;

	@:native("entry_names")
	public function entryNames(maximumEntries:Int, maximumNameBytes:Int,
		maximumSegmentBytes:Int):Result<Vec<String>, AdmissionFsError>;

	@:native("inspect_child")
	public function inspectChild(component:String):Result<PinnedChild, AdmissionFsError>;
}

/** One descriptor-relative child identity captured before its final open. */
@:native("crate::support_crate_admission_fs::PinnedChild")
extern class PinnedChild {
	@:native("open_directory")
	public function openDirectory():Result<PinnedDirectory, AdmissionFsError>;

	@:native("read_file")
	public function readFile(maximumBytes:Int):Result<Vec<Int>, AdmissionFsError>;
}
