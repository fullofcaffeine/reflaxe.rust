package supportcrate.helper;

import rust.Option;
import rust.Result;
import rust.Vec;
import rust.VecTools;
import supportcrate.helper.AdmissionProtocol.AdmissionRequest;

enum abstract AdmissionTreeKind(Int) to Int {
	var Directory = 0;
	var File = 1;
}

final class AdmissionTreeEntry {
	public final kind:AdmissionTreeKind;
	public final path:Vec<String>;
	public final logicalPath:String;
	public final bytes:Option<Vec<Int>>;

	public function new(kind:AdmissionTreeKind, path:Vec<String>, logicalPath:String, bytes:Option<Vec<Int>>) {
		this.kind = kind;
		this.path = path;
		this.logicalPath = logicalPath;
		this.bytes = bytes;
	}
}

final class AdmissionBundle {
	public final declarationRef:Int;
	public final classpathRef:Int;
	public final entries:Vec<AdmissionTreeEntry>;

	public function new(declarationRef:Int, classpathRef:Int, entries:Vec<AdmissionTreeEntry>) {
		this.declarationRef = declarationRef;
		this.classpathRef = classpathRef;
		this.entries = entries;
	}
}

final class AdmissionFailure {
	public final code:Int;
	public final declarationRef:Int;
	public final classpathRef:Int;
	public final componentIndex:Int;

	public function new(code:Int, declarationRef:Int, classpathRef:Int, componentIndex:Int) {
		this.code = code;
		this.declarationRef = declarationRef;
		this.classpathRef = classpathRef;
		this.componentIndex = componentIndex;
	}
}

/**
	Selects and copies one complete support-crate tree without full-path child reads.

	Each recursive step keeps an open parent directory. The engine applies limits
	before it retains excess names or bytes. It reads the selected tree twice,
	rejects visible changes, and returns the validated first copy in global UTF-8
	path order. The compiler performs the later manifest and Rust-source checks.
**/
final class AdmissionEngine {
	static inline final CLASSPATH_INVALID = 2;
	static inline final SOURCE_NOT_FOUND = 3;
	static inline final SOURCE_AMBIGUOUS = 4;
	static inline final SOURCE_INVALID = 5;
	static inline final SOURCE_CHANGED = 6;
	static inline final MAX_FILES = 256;
	static inline final MAX_ENTRIES = 256 * 33;
	static inline final MAX_PATH_DEPTH = 32;
	static inline final MAX_CLASSPATH_COMPONENTS = 128;
	public static inline final MAX_PATH_SEGMENT_BYTES = 255;
	static inline final MAX_FILE_BYTES = 2 * 1024 * 1024;
	static inline final MAX_CRATE_BYTES = 16 * 1024 * 1024;
	static inline final MAX_TOTAL_SOURCE_BYTES = 32 * 1024 * 1024;
	static inline final MAX_RESPONSE_BYTES = 40 * 1024 * 1024;
	static inline final RESPONSE_FRAME_BYTES = 24;
	static inline final RESPONSE_BUNDLE_BYTES = 12;
	static inline final RESPONSE_ENTRY_BYTES = 8;

	public static function admit(request:AdmissionRequest):Result<Vec<AdmissionBundle>, AdmissionFailure> {
		var bundles = new Vec<AdmissionBundle>();
		var totalSourceBytes = 0;
		var totalResponseBytes = RESPONSE_FRAME_BYTES;
		var declarationIndex = 0;
		while (declarationIndex < VecTools.len(request.declarations)) {
			var declaration = switch VecTools.get(request.declarations, declarationIndex) {
				case Some(value): value;
				case None: return Err(failure(SOURCE_INVALID, declarationIndex, -1, -1));
			};
			var selectedClasspath = -1;
			var selectedEntries = new Vec<AdmissionTreeEntry>();
			var selectedSourceBytes = 0;
			var selectedResponseBytes = 0;
			var classpathIndex = 0;
			while (classpathIndex < VecTools.len(request.classpaths)) {
				var classpath = switch VecTools.get(request.classpaths, classpathIndex) {
					case Some(value): value;
					case None: return Err(failure(SOURCE_INVALID, declaration.ref, classpathIndex, -1));
				};
				var root = switch openClasspath(classpath.path) {
					case Ok(value): value;
					case Err(_): return Err(failure(CLASSPATH_INVALID, declaration.ref, classpath.ref, -1));
				};
				switch openSourceRoot(root, declaration.sourceRoot) {
					case Err(error):
						if (!error.isNotFound())
							return Err(failure(SOURCE_INVALID, declaration.ref, classpath.ref, -1));
					case Ok(sourceRoot):
						if (selectedClasspath != -1)
							return Err(failure(SOURCE_AMBIGUOUS, declaration.ref, -1, -1));
						var remainingSourceBytes = MAX_TOTAL_SOURCE_BYTES - totalSourceBytes;
						var remainingResponseBytes = MAX_RESPONSE_BYTES - totalResponseBytes - RESPONSE_BUNDLE_BYTES;
						if (remainingSourceBytes <= 0 || remainingResponseBytes <= 0)
							return Err(failure(SOURCE_INVALID, declaration.ref, classpath.ref, -1));
						var first = switch readTree(sourceRoot.clone(), remainingSourceBytes, remainingResponseBytes) {
							case Ok(value): value;
							case Err(_): return Err(failure(SOURCE_INVALID, declaration.ref, classpath.ref, -1));
						};
						#if support_crate_admission_test_barriers
						switch AdmissionTestBarrier.afterFirstPass() {
							case Ok(_):
							case Err(_): return Err(failure(SOURCE_INVALID, declaration.ref, classpath.ref, -1));
						}
						#end
						var second = switch readTree(sourceRoot, remainingSourceBytes, remainingResponseBytes) {
							case Ok(value): value;
							case Err(_): return Err(failure(SOURCE_CHANGED, declaration.ref, classpath.ref, -1));
						};
						if (!sameTree(first.entries.clone(), second.entries.clone()))
							return Err(failure(SOURCE_CHANGED, declaration.ref, classpath.ref, -1));
						selectedClasspath = classpath.ref;
						selectedEntries = first.entries.clone();
						selectedSourceBytes = first.sourceBytes;
						selectedResponseBytes = first.responseBytes;
				}
				classpathIndex++;
			}
			if (selectedClasspath == -1)
				return Err(failure(SOURCE_NOT_FOUND, declaration.ref, -1, -1));
			totalSourceBytes += selectedSourceBytes;
			totalResponseBytes += RESPONSE_BUNDLE_BYTES + selectedResponseBytes;
			if (totalSourceBytes > MAX_TOTAL_SOURCE_BYTES || totalResponseBytes > MAX_RESPONSE_BYTES)
				return Err(failure(SOURCE_INVALID, declaration.ref, selectedClasspath, -1));
			bundles.push(new AdmissionBundle(declaration.ref, selectedClasspath, selectedEntries));
			declarationIndex++;
		}
		return Ok(bundles);
	}

	static function openClasspath(path:String):Result<PinnedDirectory, AdmissionFsError> {
		var absolute = path.length > 0 && path.charAt(0) == "/";
		var current = switch (absolute ? PinnedDirectory.openRoot() : PinnedDirectory.openCurrent()) {
			case Ok(value): value;
			case Err(error): return Err(error);
		};
		var segmentStart = absolute ? 1 : 0;
		var cursor = segmentStart;
		var componentCount = 0;
		while (cursor <= path.length) {
			if (cursor == path.length || path.charAt(cursor) == "/") {
				var component = path.substr(segmentStart, cursor - segmentStart);
				if (component.length > 0 && component != ".") {
					componentCount++;
					if (componentCount > MAX_CLASSPATH_COMPONENTS
						|| AdmissionByteTools.utf8Length(component) > MAX_PATH_SEGMENT_BYTES)
						return invalidInput();
					current = switch current.openDirectory(component) {
						case Ok(value): value;
						case Err(error): return Err(error);
					};
				}
				segmentStart = cursor + 1;
			}
			cursor++;
		}
		return Ok(current);
	}

	static function openSourceRoot(root:PinnedDirectory, segments:Vec<String>):Result<PinnedDirectory, AdmissionFsError> {
		if (VecTools.len(segments) <= 0 || VecTools.len(segments) > MAX_PATH_DEPTH)
			return invalidInput();
		var current = root;
		var index = 0;
		while (index < VecTools.len(segments)) {
			var segment = switch VecTools.get(segments, index) {
				case Some(value): value;
				case None: return Err(AdmissionFsErrorFactory.invalidInput());
			};
			if (AdmissionByteTools.utf8Length(segment) <= 0
				|| AdmissionByteTools.utf8Length(segment) > MAX_PATH_SEGMENT_BYTES)
				return invalidInput();
			current = switch current.openDirectory(segment) {
				case Ok(value): value;
				case Err(error): return Err(error);
			};
			index++;
		}
		return Ok(current);
	}

	static function readTree(root:PinnedDirectory, maximumSourceBytes:Int,
		maximumResponseBytes:Int):Result<TreeRead, AdmissionFsError> {
		var entries = new Vec<AdmissionTreeEntry>();
		var path = new Vec<String>();
		var budget = new TraversalBudget();
		return switch appendDirectory(root, path, entries, budget, 0, 0, 0, maximumSourceBytes, maximumResponseBytes) {
			case Ok(value) if (VecTools.len(value.entries) > 0 && value.fileCount > 0):
				Ok(new TreeRead(canonicalTreeOrder(value.entries.clone()), value.sourceBytes, value.fileCount, value.responseBytes));
			case Ok(_): invalidInput();
			case Err(error): Err(error);
		};
	}

	static function appendDirectory(directory:PinnedDirectory, parent:Vec<String>, entries:Vec<AdmissionTreeEntry>,
		budget:TraversalBudget, sourceBytes:Int, fileCount:Int, responseBytes:Int, maximumSourceBytes:Int,
		maximumResponseBytes:Int):Result<TreeRead, AdmissionFsError> {
		var remainingEntries = MAX_ENTRIES - VecTools.len(entries) - budget.reservedEntries;
		var remainingNameBytes = maximumResponseBytes - responseBytes - budget.reservedNameBytes;
		if (remainingEntries <= 0 || remainingNameBytes <= 0)
			return invalidInput();
		var names = switch directory.entryNames(remainingEntries, remainingNameBytes, MAX_PATH_SEGMENT_BYTES) {
			case Ok(value): value;
			case Err(error): return Err(error);
		};
		if (!budget.reserve(names.clone(), remainingEntries, remainingNameBytes))
			return invalidInput();
		var index = 0;
		while (index < VecTools.len(names)) {
			if (VecTools.len(entries) >= MAX_ENTRIES)
				return invalidInput();
			var name = switch VecTools.get(names, index) {
				case Some(value): value;
				case None: return invalidInput();
			};
			if (!budget.release(name))
				return invalidInput();
			var path = parent.clone();
			path.push(name);
			if (VecTools.len(path) > MAX_PATH_DEPTH)
				return invalidInput();
			var entryBytes = encodedEntryBytes(path.clone());
			if (entryBytes < RESPONSE_ENTRY_BYTES || responseBytes + entryBytes > maximumResponseBytes)
				return invalidInput();
			var child = switch directory.inspectChild(name) {
				case Ok(value): value;
				case Err(error): return Err(error);
			};
			#if support_crate_admission_test_barriers
			switch AdmissionTestBarrier.beforeChildOpen(name) {
				case Ok(_):
				case Err(error): return Err(error);
			}
			#end
			switch child.openDirectory() {
				case Ok(child):
					entries.push(new AdmissionTreeEntry(Directory, path.clone(), logicalPath(path.clone()), None));
					responseBytes += entryBytes;
					switch appendDirectory(child, path, entries, budget, sourceBytes, fileCount, responseBytes,
						maximumSourceBytes, maximumResponseBytes) {
						case Ok(nested):
							entries = nested.entries;
							sourceBytes = nested.sourceBytes;
							fileCount = nested.fileCount;
							responseBytes = nested.responseBytes;
						case Err(error): return Err(error);
					}
				case Err(directoryError):
					if (!directoryError.isWrongKind())
						return Err(directoryError);
					if (fileCount >= MAX_FILES)
						return invalidInput();
					var remainingFileBytes = MAX_FILE_BYTES;
					if (maximumSourceBytes - sourceBytes < remainingFileBytes)
						remainingFileBytes = maximumSourceBytes - sourceBytes;
					if (MAX_CRATE_BYTES - sourceBytes < remainingFileBytes)
						remainingFileBytes = MAX_CRATE_BYTES - sourceBytes;
					if (maximumResponseBytes - responseBytes - entryBytes < remainingFileBytes)
						remainingFileBytes = maximumResponseBytes - responseBytes - entryBytes;
					if (remainingFileBytes <= 0)
						return invalidInput();
					var bytes = switch child.readFile(remainingFileBytes) {
						case Ok(value): value;
						case Err(error): return Err(error);
					};
					fileCount++;
					sourceBytes += AdmissionByteTools.length(bytes);
					responseBytes += entryBytes + AdmissionByteTools.length(bytes);
					if (fileCount > MAX_FILES || sourceBytes > MAX_CRATE_BYTES || sourceBytes > maximumSourceBytes
						|| responseBytes > maximumResponseBytes)
						return invalidInput();
					entries.push(new AdmissionTreeEntry(File, path.clone(), logicalPath(path), Some(bytes)));
			}
			index++;
		}
		return Ok(new TreeRead(entries, sourceBytes, fileCount, responseBytes));
	}

	static function encodedEntryBytes(path:Vec<String>):Int {
		var bytes = RESPONSE_ENTRY_BYTES;
		var index = 0;
		while (index < VecTools.len(path)) {
			switch VecTools.get(path, index) {
				case Some(segment): bytes += 2 + AdmissionByteTools.utf8Length(segment);
				case None: return -1;
			}
			index++;
		}
		return bytes;
	}

	static function canonicalTreeOrder(entries:Vec<AdmissionTreeEntry>):Vec<AdmissionTreeEntry> {
		var width = 1;
		var source = entries;
		var length = VecTools.len(source);
		while (width < length) {
			var target = new Vec<AdmissionTreeEntry>();
			var start = 0;
			while (start < length) {
				var left = start;
				var right = start + width;
				var leftEnd = right < length ? right : length;
				var rightEnd = start + width * 2 < length ? start + width * 2 : length;
				while (left < leftEnd || right < rightEnd) {
					var takeLeft = right >= rightEnd;
					if (!takeLeft && left < leftEnd) {
						var leftValue = VecTools.get(source, left);
						var rightValue = VecTools.get(source, right);
						takeLeft = switch [leftValue, rightValue] {
							case [Some(a), Some(b)]: AdmissionByteTools.compareUtf8(a.logicalPath, b.logicalPath) <= 0;
							case [Some(_), None]: true;
							case _: false;
						};
					}
					var selected = takeLeft ? VecTools.get(source, left++) : VecTools.get(source, right++);
					switch selected {
						case Some(value): target.push(value);
						case None:
					}
				}
				start += width * 2;
			}
			source = target;
			width *= 2;
		}
		return source;
	}

	static function logicalPath(path:Vec<String>):String {
		var result = "";
		var index = 0;
		while (index < VecTools.len(path)) {
			switch VecTools.get(path, index) {
				case Some(segment):
					if (index > 0)
						result += "/";
					result += segment;
				case None:
			}
			index++;
		}
		return result;
	}

	static function sameTree(left:Vec<AdmissionTreeEntry>, right:Vec<AdmissionTreeEntry>):Bool {
		if (VecTools.len(left) != VecTools.len(right))
			return false;
		var index = 0;
		while (index < VecTools.len(left)) {
			var leftEntry = switch VecTools.get(left, index) {
				case Some(value): value;
				case None: return false;
			};
			var rightEntry = switch VecTools.get(right, index) {
				case Some(value): value;
				case None: return false;
			};
			if (leftEntry.kind != rightEntry.kind || !samePath(leftEntry.path, rightEntry.path))
				return false;
			switch leftEntry.bytes {
				case None:
					switch rightEntry.bytes {
						case None:
						case Some(_): return false;
					}
				case Some(leftBytes):
					switch rightEntry.bytes {
						case None: return false;
						case Some(rightBytes):
							if (!AdmissionByteTools.equal(leftBytes, rightBytes))
								return false;
					}
			}
			index++;
		}
		return true;
	}

	static function samePath(left:Vec<String>, right:Vec<String>):Bool {
		if (VecTools.len(left) != VecTools.len(right))
			return false;
		var index = 0;
		while (index < VecTools.len(left)) {
			if (VecTools.get(left, index) != VecTools.get(right, index))
				return false;
			index++;
		}
		return true;
	}

	static function invalidInput<T>():Result<T, AdmissionFsError> {
		return Err(AdmissionFsErrorFactory.invalidInput());
	}

	static function failure(code:Int, declarationRef:Int, classpathRef:Int, componentIndex:Int):AdmissionFailure {
		return new AdmissionFailure(code, declarationRef, classpathRef, componentIndex);
	}
}

private final class TreeRead {
	public final entries:Vec<AdmissionTreeEntry>;
	public final sourceBytes:Int;
	public final fileCount:Int;
	public final responseBytes:Int;

	public function new(entries:Vec<AdmissionTreeEntry>, sourceBytes:Int, fileCount:Int, responseBytes:Int) {
		this.entries = entries;
		this.sourceBytes = sourceBytes;
		this.fileCount = fileCount;
		this.responseBytes = responseBytes;
	}
}

/** Tracks names retained by every active recursive directory enumeration. */
private final class TraversalBudget {
	public var reservedEntries = 0;
	public var reservedNameBytes = 0;

	public function new() {}

	public function reserve(names:Vec<String>, maximumEntries:Int, maximumNameBytes:Int):Bool {
		var entryCount = VecTools.len(names);
		if (entryCount > maximumEntries)
			return false;
		var nameBytes = 0;
		var index = 0;
		while (index < entryCount) {
			var name = switch VecTools.get(names, index) {
				case Some(value): value;
				case None: return false;
			};
			var length = AdmissionByteTools.utf8Length(name);
			if (length <= 0 || length > AdmissionEngine.MAX_PATH_SEGMENT_BYTES
				|| nameBytes > maximumNameBytes - length)
				return false;
			nameBytes += length;
			index++;
		}
		reservedEntries += entryCount;
		reservedNameBytes += nameBytes;
		return true;
	}

	public function release(name:String):Bool {
		var length = AdmissionByteTools.utf8Length(name);
		if (reservedEntries <= 0 || length <= 0 || length > reservedNameBytes)
			return false;
		reservedEntries--;
		reservedNameBytes -= length;
		return true;
	}
}
