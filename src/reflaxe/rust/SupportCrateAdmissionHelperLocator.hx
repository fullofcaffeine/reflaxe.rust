package reflaxe.rust;

#if macro
import eval.luv.SystemInfo;
import haxe.io.Path;
import sys.FileSystem;

/** Closed reasons why this process cannot select a packaged Stage 2B helper. */
enum abstract SupportCrateAdmissionHelperUnavailable(Int) to Int {
	var UnsupportedHost = 1;
	var LoadedCompilerUnavailable = 2;
	var PackageLayoutInvalid = 3;
}

/** Private process-local helper locator. Neither path is durable semantic identity. */
final class SupportCrateAdmissionHelperLocation {
	public final packageRoot:String;
	public final executablePath:String;
	public final expectedSha256:String; // numeric-suffix-guard: allow-standard-encoding (SHA-256)

	public function new(packageRoot:String, executablePath:String,
		expectedSha256:String) { // numeric-suffix-guard: allow-standard-encoding (SHA-256)
		this.packageRoot = packageRoot;
		this.executablePath = executablePath;
		this.expectedSha256 = expectedSha256;
	}
}

/** Host-gated result of locating the package-owned helper. */
enum SupportCrateAdmissionHelperLocatorResult {
	Available(value:SupportCrateAdmissionHelperLocation);
	Unavailable(reason:SupportCrateAdmissionHelperUnavailable);
}

/**
	Locates the package-owned helper for the current supported host.

	The returned path is only a process-local locator. Later code must verify and execute
	the package-owned helper before any support-crate source can become authoritative.
**/
final class SupportCrateAdmissionHelperLocator {
	static inline var DARWIN_ARM64_HELPER:String = "native/support-crate-admission/darwin-arm64/hxrs-support-crate-admission";
	static inline var DARWIN_ARM64_SHA256:String = "eb68f7a6c9b9dddeed93e15aef22f185a4a84242f88f97cd9530d0b6bf614add"; // numeric-suffix-guard: allow-standard-encoding (SHA-256)

	public static function locate(packageRoot:Null<String>):SupportCrateAdmissionHelperLocatorResult {
		var machine:Null<String> = null;
		try {
			machine = SystemInfo.uname().resolve().machine;
		} catch (_:haxe.Exception) {}
		return locateForHost(Sys.systemName(), machine, packageRoot);
	}

	static function locateForHost(systemName:String, machine:Null<String>, packageRoot:Null<String>):SupportCrateAdmissionHelperLocatorResult {
		var helper = switch [systemName, machine] {
			case ["Mac", "arm64"] | ["Darwin", "arm64"]: {
				relativePath: DARWIN_ARM64_HELPER,
				sha256: DARWIN_ARM64_SHA256
			};
			case _: null;
		};
		if (helper == null)
			return Unavailable(UnsupportedHost);
		if (packageRoot == null)
			return Unavailable(LoadedCompilerUnavailable);
		return Available(new SupportCrateAdmissionHelperLocation(packageRoot, Path.normalize(Path.join([
			packageRoot,
			helper.relativePath
		])), helper.sha256));
	}

	public static function anchorPackageRoot(sourceFile:String):Null<String> {
		try {
			var absolute = Path.normalize(FileSystem.fullPath(sourceFile));
			if (Path.withoutDirectory(absolute) != "RustCompiler.hx")
				return null;
			var rustDirectory = Path.directory(absolute);
			if (Path.withoutDirectory(rustDirectory) != "rust")
				return null;
			var reflaxeDirectory = Path.directory(rustDirectory);
			if (Path.withoutDirectory(reflaxeDirectory) != "reflaxe")
				return null;
			var sourceDirectory = Path.directory(reflaxeDirectory);
			if (Path.withoutDirectory(sourceDirectory) != "src")
				return null;
			return Path.directory(sourceDirectory);
		} catch (_:haxe.Exception) {
			return null;
		}
	}
}
#end
