package supportcrate.helper;

#if support_crate_admission_test_barriers
import rust.Result;

/** Test-only native barrier for deterministic source-replacement fixtures. */
@:native("crate::support_crate_admission_test_barrier::AdmissionTestBarrier")
@:rustExtraSrc("support_crate_admission_test_barrier.rs")
extern class AdmissionTestBarrier {
	@:native("after_first_pass")
	public static function afterFirstPass():Result<Void, AdmissionFsError>;

	@:native("before_child_open")
	public static function beforeChildOpen(component:String):Result<Void, AdmissionFsError>;
}
#end
