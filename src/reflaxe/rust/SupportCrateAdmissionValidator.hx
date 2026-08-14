package reflaxe.rust;

#if macro
import haxe.Exception;
import haxe.crypto.Sha256;
import haxe.io.Bytes;
import reflaxe.rust.SupportCrateAdmissionProtocol.SupportCrateAdmissionAccepted;
import reflaxe.rust.SupportCrateAdmissionProtocol.SupportCrateAdmissionTreeEntry;
import reflaxe.rust.SupportCratePlan.SupportCratePlan;
import reflaxe.rust.SupportCratePlan.SupportCratePlanEntry;
import reflaxe.rust.SupportCratePlan.SupportCrateSourceFile;
import reflaxe.rust.SupportCrateRequestPlan.SupportCrateRequestPlan;
import reflaxe.rust.naming.RustNaming;

/** A helper response is not source authority until this independent validation succeeds. */
final class SupportCrateAdmissionValidationFailure extends Exception {}

/**
	Converts a complete helper response into an immutable source plan.

	The helper owns descriptor-relative filesystem facts. This validator does not
	trust it to define the language-level bundle. It independently checks every
	logical path, file byte, parent directory, budget, and Cargo manifest before it
	creates a plan. The returned plan contains copied bytes and no host path.
**/
final class SupportCrateAdmissionValidator {
	public static function validate(requestPlan:SupportCrateRequestPlan, accepted:SupportCrateAdmissionAccepted):SupportCratePlan {
		var requests = requestPlan.requests();
		var bundles = accepted.bundles();
		if (bundles.length != requests.length)
			fail();
		var planned = new Array<SupportCratePlanEntry>();
		var totalBytes = 0;
		for (index in 0...requests.length) {
			var request = requests[index];
			var bundle = bundles[index];
			if (bundle.declarationRef != index)
				fail();
			var validated = validateTree(request, bundle.entries());
			totalBytes += validated.sourceBytes;
			if (totalBytes > SupportCrateAdmissionProtocol.MAX_TOTAL_SOURCE_BYTES)
				fail();
			planned.push(new SupportCratePlanEntry(request, bundle.selectedClasspathRef, validated.files));
		}
		return new SupportCratePlan(planned);
	}

	static function validateTree(request:reflaxe.rust.SupportCrateRequestPlan.SupportCrateRequest,
		entries:Array<SupportCrateAdmissionTreeEntry>):{files:Array<SupportCrateSourceFile>, sourceBytes:Int} {
		if (entries.length < 1 || entries.length > SupportCrateAdmissionProtocol.MAX_TREE_ENTRIES_PER_CRATE)
			fail();
		var directories:Map<String, Bool> = [];
		var filePaths:Map<String, Bool> = [];
		var files = new Array<SupportCrateSourceFile>();
		var lastPath:Null<Bytes> = null;
		var manifest:Null<Bytes> = null;
		var hasLibrary = false;
		var sourceBytes = 0;
		for (entry in entries) {
			var segments = entry.pathSegments();
			if (segments.length < 1 || segments.length > SupportCrateAdmissionProtocol.MAX_PATH_DEPTH)
				fail();
			var relativePath = segments.join('/');
			var encodedPath = Bytes.ofString(relativePath);
			if (lastPath != null && lastPath.compare(encodedPath) >= 0)
				fail();
			lastPath = encodedPath;
			validateParentDirectories(segments, directories);
			switch entry.kind {
				case Directory:
					if (!validDirectoryPath(segments) || entry.fileBytes() != null || directories.exists(relativePath)
						|| filePaths.exists(relativePath))
						fail();
					directories.set(relativePath, true);
				case File:
					var bytes = entry.fileBytes();
					if (bytes == null || filePaths.exists(relativePath) || directories.exists(relativePath))
						fail();
					filePaths.set(relativePath, true);
					if (relativePath == 'Cargo.toml') {
						if (manifest != null)
							fail();
						manifest = bytes;
					} else {
						if (!validRustSourcePath(segments) || !canonicalText(bytes))
							fail();
						if (relativePath == 'src/lib.rs')
							hasLibrary = true;
					}
					sourceBytes += bytes.length;
					if (files.length >= SupportCrateAdmissionProtocol.MAX_FILES_PER_CRATE
						|| bytes.length > SupportCrateAdmissionProtocol.MAX_FILE_BYTES
						|| sourceBytes > SupportCrateAdmissionProtocol.MAX_CRATE_BYTES)
						fail();
					files.push(new SupportCrateSourceFile(relativePath, bytes, Sha256.make(bytes).toHex()));
			}
		}
		if (manifest == null || !hasLibrary || !directories.exists('src')
			|| manifest.compare(SupportCrateManifestRenderer.render(request)) != 0)
			fail();
		for (directory in directories.keys()) {
			var prefix = directory + '/';
			var containsFile = false;
			for (file in files) {
				if (StringTools.startsWith(file.relativePath, prefix)) {
					containsFile = true;
					break;
				}
			}
			if (!containsFile)
				fail();
		}
		return {files: files, sourceBytes: sourceBytes};
	}

	static function validateParentDirectories(segments:Array<String>, directories:Map<String, Bool>):Void {
		if (segments.length < 2)
			return;
		for (length in 1...segments.length) {
			var parent = segments.slice(0, length).join('/');
			if (!directories.exists(parent))
				fail();
		}
	}

	static function validDirectoryPath(segments:Array<String>):Bool {
		if (segments[0] != 'src')
			return false;
		for (segment in segments)
			if (!validLowerRustIdentifier(segment))
				return false;
		return true;
	}

	static function validRustSourcePath(segments:Array<String>):Bool {
		if (segments.length < 2 || segments[0] != 'src')
			return false;
		for (index in 1...(segments.length - 1))
			if (!validLowerRustIdentifier(segments[index]))
				return false;
		var file = segments[segments.length - 1];
		if (!StringTools.endsWith(file, '.rs'))
			return false;
		var stem = file.substr(0, file.length - 3);
		return stem == 'mod' || validLowerRustIdentifier(stem);
	}

	static function validLowerRustIdentifier(value:String):Bool {
		if (value == null || value.length == 0 || value == '_' || RustNaming.isRustKeyword(value))
			return false;
		for (index in 0...value.length) {
			var code = value.charCodeAt(index);
			var lower = code >= 'a'.code && code <= 'z'.code;
			var digit = code >= '0'.code && code <= '9'.code;
			if (!lower && code != '_'.code && !(digit && index > 0))
				return false;
		}
		return true;
	}

	static function canonicalText(bytes:Bytes):Bool {
		if (bytes.length >= 3 && bytes.get(0) == 0xef && bytes.get(1) == 0xbb && bytes.get(2) == 0xbf)
			return false;
		for (index in 0...bytes.length) {
			var byte = bytes.get(index);
			if (byte == 0 || byte == 13)
				return false;
		}
		var value:String;
		try {
			value = bytes.toString();
		} catch (_:Exception) {
			return false;
		}
		return Bytes.ofString(value).compare(bytes) == 0;
	}

	static function fail<T>():T {
		throw new SupportCrateAdmissionValidationFailure('support-crate admission response failed independent validation');
	}
}
#end
