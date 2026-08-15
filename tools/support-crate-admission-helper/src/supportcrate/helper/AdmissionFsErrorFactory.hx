package supportcrate.helper;

/** Creates closed errors without exposing a native constructor to the helper. */
@:native("crate::support_crate_admission_fs::AdmissionFsErrorFactory")
@:rustCargo({name: "rustix", version: "=1.1.4", defaultFeatures: false, features: ["std", "fs"]})
@:rustExtraSrc("support_crate_admission_fs.rs")
extern class AdmissionFsErrorFactory {
	@:native("invalid_input")
	public static function invalidInput():AdmissionFsError;
}
