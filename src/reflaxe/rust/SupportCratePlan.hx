package reflaxe.rust;

#if macro
import haxe.io.Bytes;
import reflaxe.rust.SupportCrateRequestPlan.SupportCrateRequest;

/** One copied, validated source file with no machine-local locator. */
final class SupportCrateSourceFile {
	public final relativePath:String;
	public final sha256:String; // numeric-suffix-guard: allow-standard-encoding (SHA-256)
	final byteValues:Bytes;

	public function new(relativePath:String, bytes:Bytes,
		sha256:String) { // numeric-suffix-guard: allow-standard-encoding (SHA-256)
		this.relativePath = relativePath;
		this.byteValues = bytes.sub(0, bytes.length);
		this.sha256 = sha256;
	}

	public function bytes():Bytes {
		return byteValues.sub(0, byteValues.length);
	}
}

/** One request plus the exact helper-selected classpath ordinal and admitted bytes. */
final class SupportCratePlanEntry {
	public final request:SupportCrateRequest;
	public final selectedClasspathRef:Int;
	final sourceFileValues:Array<SupportCrateSourceFile>;

	public function new(request:SupportCrateRequest, selectedClasspathRef:Int, sourceFiles:Array<SupportCrateSourceFile>) {
		this.request = request;
		this.selectedClasspathRef = selectedClasspathRef;
		this.sourceFileValues = sourceFiles.copy();
	}

	public function sourceFiles():Array<SupportCrateSourceFile> {
		return sourceFileValues.copy();
	}
}

/** Request-local Stage 2B authority over copied and independently validated source bytes. */
final class SupportCratePlan {
	final entryValues:Array<SupportCratePlanEntry>;

	public function new(entries:Array<SupportCratePlanEntry>) {
		this.entryValues = entries.copy();
	}

	public function entries():Array<SupportCratePlanEntry> {
		return entryValues.copy();
	}
}
#end
