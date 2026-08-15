package supportcrate.helper;

/** Closed filesystem failures from the descriptor-relative native boundary. */
@:native("crate::support_crate_admission_fs::AdmissionFsError")
@:rustCargo({name: "rustix", version: "=1.1.4", defaultFeatures: false, features: ["std", "fs"]})
@:rustExtraSrc("support_crate_admission_fs.rs")
extern class AdmissionFsError {
	@:native("is_invalid_input")
	public function isInvalidInput():Bool;

	@:native("is_not_found")
	public function isNotFound():Bool;

	@:native("is_wrong_kind")
	public function isWrongKind():Bool;

	@:native("is_io")
	public function isIo():Bool;
}
