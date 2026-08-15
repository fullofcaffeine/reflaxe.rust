package reflaxe.rust;

#if macro
/** Adversarial late classpath entry. The already-loaded compiler anchor must ignore it. */
final class RustCompiler {
	public static final shadowMarker:String = "must-not-own-helper-location";
}
#end
