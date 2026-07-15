package reflaxe.rust.ast;

import haxe.macro.Expr.Position;
import reflaxe.rust.naming.RustNaming;

/**
 * Minimal Rust AST for the reflaxe.rust compiler.
 *
 * Keep this deliberately small and extend as codegen needs grow.
 */
// Main module type (required for Haxe module/type resolution).
class RustAST {}

/**
	Describes whether a Rust IR node came from Haxe source or was synthesized by the backend.

	Why
	- Diagnostics and policy passes must distinguish user authority from compiler implementation
	  details without guessing from printed Rust text.
	- A missing position is not equivalent to user source: generated scaffolding needs an explicit
	  origin so later source-map work can report it honestly.

	What
	- `OriginHaxeSource` retains the exact typed-AST position supplied by Haxe.
	- `OriginCompilerGenerated` marks syntax with no single honest Haxe source position.

	How
	- Raw-fragment factories require one of these origins today. Later typed IR nodes can reuse the
	  same origin without changing Rust output.
**/
enum RustOrigin {
	OriginHaxeSource(pos:Position);
	OriginCompilerGenerated;
}

/**
	Closed reasons for compiler-owned Rust text that has not yet migrated to structural IR.

	Why
	- `RRaw` and `ERaw` are analysis blind spots. Treating every compiler string as equivalent makes
	  it impossible to prioritize migration or tell source authority from backend debt.

	What
	- Each constructor identifies one current compiler lowering family. These reasons describe
	  migration debt; they do not authorize adding more raw lowering.

	How
	- `RustRawCode` maps every constructor to a stable identifier. Adding a constructor therefore
	  requires updating the exhaustive mapping and reviewing the new authority explicitly.
**/
enum RustCompilerRawReason {
	RawGeneratedFileMarker;
	RawStaticStorage;
	RawCrateHeader;
	RawNestedModuleDeclarations;
	RawInterfaceTraitDeclaration;
	RawBaseTraitImport;
	RawTypeIdConstant;
	RawDeriveAttribute;
	RawClassTraitDeclaration;
	RawClassTraitImplementation;
	RawBaseTraitImplementation;
	RawInterfaceTraitImplementation;
	RawGeneratedTestModule;
	RawDefaultValueFallback;
	RawUnsupportedFallback;
}

/**
	Closed reasons for Rust text deliberately supplied through Haxe metadata.

	Why
	- Metadata is user authority even when the compiler renders its surrounding syntax.
	- Keeping it separate prevents a future compiler migration from silently claiming ownership of
	  source-provided Rust bodies or target paths.

	What
	- Currently covers the raw `@:rustImpl` contract.

	How
	- The metadata factory always requires the metadata's Haxe position.
**/
enum RustMetadataRawReason {
	RawTraitImplementation;
}

/**
	Closed reasons for Rust expressions supplied verbatim by source code.

	Why
	- Explicit target-code injection is a real escape hatch and must never be confused with typed
	  compiler lowering merely because both eventually print Rust text.

	What
	- Currently covers the configured `__rust__` target-code injection boundary.

	How
	- The source factory requires an exact Haxe position and remains visible to metal restrictions.
	- This records emission ownership only; it never grants `@:rustAllowRaw` permission or weakens
	  strict/metal boundary enforcement.
**/
enum RustSourceRawReason {
	RawTargetCodeInjection;
}

/**
	Identifies who owns an intentionally raw Rust fragment.

	Why
	- Policy passes need a typed distinction between compiler migration debt, metadata authority, and
	  explicit source injection.

	What
	- Wraps one of three closed reason enums rather than accepting a free-form label.

	How
	- Instances can only be created through `RustRawCode` factories, which pair authority with a
	  source origin.
**/
enum RustRawAuthority {
	RawCompilerOwned(reason:RustCompilerRawReason);
	RawMetadataOwned(reason:RustMetadataRawReason);
	RawSourceOwned(reason:RustSourceRawReason);
}

/**
	A classified raw Rust fragment carried by `RRaw` or `ERaw`.

	Why
	- Plain strings erase both authority and Haxe provenance, so compiler passes cannot distinguish an
	  intentional escape hatch from syntax that should become typed IR.
	- Public construction would allow new raw text to bypass that classification.

	What
	- Stores the exact printable bytes plus a closed authority/reason and explicit origin.
	- Exposes stable identifiers for reports and policy diagnostics.

	How
	- The constructor is private. Callers select `compilerGenerated`, `compilerAt`, `metadataAt`, or
	  `sourceAt`; `withCode` is the only transformation helper and preserves metadata byte-for-byte.
	- The printer reads only `code`, so classification cannot alter generated Rust.
**/
class RustRawCode {
	public final code:String;
	public final authority:RustRawAuthority;
	public final origin:RustOrigin;

	private function new(code:String, authority:RustRawAuthority, origin:RustOrigin) {
		this.code = code;
		this.authority = authority;
		this.origin = origin;
	}

	public static function compilerGenerated(code:String, reason:RustCompilerRawReason):RustRawCode {
		return new RustRawCode(code, RawCompilerOwned(reason), OriginCompilerGenerated);
	}

	public static function compilerAt(code:String, reason:RustCompilerRawReason, pos:Position):RustRawCode {
		return new RustRawCode(code, RawCompilerOwned(reason), OriginHaxeSource(pos));
	}

	public static function metadataAt(code:String, reason:RustMetadataRawReason, pos:Position):RustRawCode {
		return new RustRawCode(code, RawMetadataOwned(reason), OriginHaxeSource(pos));
	}

	public static function sourceAt(code:String, reason:RustSourceRawReason, pos:Position):RustRawCode {
		return new RustRawCode(code, RawSourceOwned(reason), OriginHaxeSource(pos));
	}

	public function withCode(nextCode:String):RustRawCode {
		return new RustRawCode(nextCode, authority, origin);
	}

	public function authorityId():String {
		return switch (authority) {
			case RawCompilerOwned(_): "compiler-owned";
			case RawMetadataOwned(_): "metadata-owned";
			case RawSourceOwned(_): "source-owned";
		};
	}

	public function reasonId():String {
		return switch (authority) {
			case RawCompilerOwned(reason): switch (reason) {
					case RawGeneratedFileMarker: "generated-file-marker";
					case RawStaticStorage: "static-storage";
					case RawCrateHeader: "crate-header";
					case RawNestedModuleDeclarations: "nested-module-declarations";
					case RawInterfaceTraitDeclaration: "interface-trait-declaration";
					case RawBaseTraitImport: "base-trait-import";
					case RawTypeIdConstant: "type-id-constant";
					case RawDeriveAttribute: "derive-attribute";
					case RawClassTraitDeclaration: "class-trait-declaration";
					case RawClassTraitImplementation: "class-trait-implementation";
					case RawBaseTraitImplementation: "base-trait-implementation";
					case RawInterfaceTraitImplementation: "interface-trait-implementation";
					case RawGeneratedTestModule: "generated-test-module";
					case RawDefaultValueFallback: "default-value-fallback";
					case RawUnsupportedFallback: "unsupported-fallback";
				}
			case RawMetadataOwned(reason): switch (reason) {
					case RawTraitImplementation: "trait-implementation";
				}
			case RawSourceOwned(reason): switch (reason) {
					case RawTargetCodeInjection: "target-code-injection";
				}
		};
	}
}

/**
	A validated Rust identifier stored without target punctuation.

	Why
	- A path held as one `String` hides module boundaries, generic arguments, and local identity from
	  compiler passes.
	- Splitting a path is only safe if each segment is already known to be a legal identifier; letting
	  `::`, `<...>`, or a keyword enter this value would recreate raw target syntax one string lower.

	What
	- Stores the ASCII identifier subset emitted by this backend and whether it must print as a Rust
	  raw identifier (`r#name`).
	- Rust path keywords (`crate`, `self`, `super`, and `Self`) are represented by `RustPathRoot`, not
	  by pretending they are ordinary identifiers.

	How
	- Use `named` for an ordinary identifier and `raw` for an intentional raw identifier.
	- Construction is private; both factories validate the spelling and keyword contract.
	- The printer, not this type, owns the `r#` prefix.
**/
class RustIdentifier {
	public final name:String;
	public final isRaw:Bool;

	private function new(name:String, isRaw:Bool) {
		this.name = name;
		this.isRaw = isRaw;
	}

	public static function named(name:String):RustIdentifier {
		validateSpelling(name);
		if (RustNaming.isRustKeyword(name))
			throw 'Rust keyword `$name` requires an explicit raw identifier or structural path root';
		return new RustIdentifier(name, false);
	}

	public static function raw(name:String):RustIdentifier {
		validateSpelling(name);
		if (name == "crate" || name == "self" || name == "super" || name == "Self")
			throw 'Rust path keyword `$name` cannot be used as a raw identifier';
		return new RustIdentifier(name, true);
	}

	public function equals(other:RustIdentifier):Bool {
		return other != null && name == other.name && isRaw == other.isRaw;
	}

	static function validateSpelling(name:String):Void {
		if (name == null || name.length == 0)
			throw "Rust identifier cannot be empty";
		if (name == "_" || !RustNaming.isValidIdent(name))
			throw 'Invalid Rust identifier `$name`; target punctuation belongs in structural IR';
	}
}

/** Identifies which closed form a `RustLifetime` carries. */
enum RustLifetimeKind {
	LifetimeNamed;
	LifetimeStatic;
	LifetimeInferred;
}

/**
	A Rust lifetime stored independently from its leading apostrophe.

	Why
	- Lifetimes participate in references, generic arguments, bounds, and declarations. A rendered
	  token such as `'a` cannot tell those roles apart and encourages string concatenation.

	What
	- Represents a validated named lifetime, the special `'static` lifetime, or the inferred `'_`
	  lifetime as closed alternatives.

	How
	- `named` accepts the bare identifier (`a`, not `'a`).
	- Use `staticLifetime` and `inferred` for Rust's special lifetime forms.
	- The printer owns the apostrophe.
**/
class RustLifetime {
	public final kind:RustLifetimeKind;
	public final name:Null<RustIdentifier>;

	private function new(kind:RustLifetimeKind, name:Null<RustIdentifier>) {
		this.kind = kind;
		this.name = name;
	}

	public static function named(name:String):RustLifetime {
		return new RustLifetime(LifetimeNamed, RustIdentifier.named(name));
	}

	public static function staticLifetime():RustLifetime {
		return new RustLifetime(LifetimeStatic, null);
	}

	public static function inferred():RustLifetime {
		return new RustLifetime(LifetimeInferred, null);
	}

	public function isNamed():Bool {
		return kind == LifetimeNamed;
	}
}

/** Identifies the payload carried by a structural Rust const argument. */
enum RustConstArgumentKind {
	ConstInteger;
	ConstBoolean;
	ConstPath;
}

/**
	A closed const-generic argument that cannot contain rendered Rust syntax.

	Why
	- Const arguments share `<...>` with types and lifetimes but have different semantics. Storing all
	  three as strings prevents traversal and can make punctuation ambiguous.

	What
	- Covers non-negative integer literals, booleans, and structural const paths, which are the closed
	  forms needed by the current compiler roadmap.

	How
	- Use the validating factories below. More complex const expressions must gain a typed AST node;
	  callers must not smuggle them through a string fallback.
**/
class RustConstArgument {
	public final kind:RustConstArgumentKind;
	public final integerDigits:Null<String>;
	public final boolValue:Null<Bool>;
	public final pathValue:Null<RustPath>;

	private function new(kind:RustConstArgumentKind, integerDigits:Null<String>, boolValue:Null<Bool>, pathValue:Null<RustPath>) {
		this.kind = kind;
		this.integerDigits = integerDigits;
		this.boolValue = boolValue;
		this.pathValue = pathValue;
	}

	public static function integer(value:Int):RustConstArgument {
		if (value < 0)
			throw "Negative const arguments require a future typed const-expression node";
		return decimalInteger(Std.string(value));
	}

	/**
		Constructs an arbitrarily wide non-negative decimal const integer.

		Why
		- Haxe `Int` is not wide enough for Rust `u64`/`usize` const arguments.

		What
		- Accepts decimal digits only and canonicalizes leading zeroes.

		How
		- This is a validated literal-token boundary, not a general Rust-expression string escape.
	**/
	public static function decimalInteger(digits:String):RustConstArgument {
		if (digits == null || digits.length == 0 || !~/^[0-9]+$/.match(digits))
			throw 'Invalid Rust decimal const integer `$digits`';
		var firstNonZero = 0;
		while (firstNonZero < digits.length - 1 && digits.charAt(firstNonZero) == "0")
			firstNonZero++;
		return new RustConstArgument(ConstInteger, digits.substr(firstNonZero), null, null);
	}

	public static function boolean(value:Bool):RustConstArgument {
		return new RustConstArgument(ConstBoolean, null, value, null);
	}

	public static function path(value:RustPath):RustConstArgument {
		if (value == null)
			throw "Rust const path cannot be null";
		return new RustConstArgument(ConstPath, null, null, value);
	}
}

/** A type, const, or lifetime argument inside a Rust path segment's angle arguments. */
enum RustGenericArgument {
	GenericType(type:RustType);
	GenericConst(argument:RustConstArgument);
	GenericLifetime(lifetime:RustLifetime);
}

/** Expresses whether a trait bound is ordinary (`Trait`) or relaxed (`?Trait`). */
enum RustTraitBoundModifier {
	TraitBoundRequired;
	TraitBoundOptional;
}

/** A trait or lifetime bound attached to a Rust type parameter. */
enum RustGenericBound {
	GenericTraitBound(path:RustPath, modifier:RustTraitBoundModifier);
	GenericLifetimeBound(lifetime:RustLifetime);
}

/**
	A structural declaration parameter for a Rust item or function.

	Why
	- Declaration strings such as `T: Clone + Send + 'static` hide which bounds are traits and which
	  are lifetimes, preventing ownership and thread-crossing analysis.

	What
	- Separates lifetime, type, and const parameter declarations with typed bounds and defaults.

	How
	- Names are already validated `RustIdentifier` values.
	- Wrap arrays of these declarations in `RustGenericParameters` to validate ordering and duplicate
	  names before attaching them to an AST declaration.
**/
enum RustGenericParameter {
	GenericLifetimeParam(name:RustIdentifier, bounds:Array<RustLifetime>);
	GenericTypeParam(name:RustIdentifier, bounds:Array<RustGenericBound>, defaultType:Null<RustType>);
	GenericConstParam(name:RustIdentifier, type:RustType, defaultValue:Null<RustConstArgument>);
}

/**
	An ordered, validated list of Rust declaration generic parameters.

	Why
	- Rust requires lifetime parameters to precede type and const parameters. Plain arrays permit an
	  invalid ordering and duplicate declarations to reach the printer.

	What
	- Owns a defensive copy of structural generic parameters and exposes read-only traversal methods.

	How
	- Construct with `of`; malformed order and duplicate names fail immediately at the AST boundary.
	- The printer consumes `count`, `at`, or `iterator` and owns delimiters and commas.
**/
class RustGenericParameters {
	final parameters:Array<RustGenericParameter>;
	public var count(get, never):Int;

	private function new(parameters:Array<RustGenericParameter>) {
		this.parameters = parameters;
	}

	public static function of(values:Array<RustGenericParameter>):RustGenericParameters {
		if (values == null)
			throw "Rust generic parameter list cannot be null";
		var copy = values.copy();
		var sawTypeOrConst = false;
		var lifetimeNames:Map<String, Bool> = [];
		var valueNames:Map<String, Bool> = [];
		for (parameter in copy) {
			if (parameter == null)
				throw "Rust generic parameter cannot be null";
			switch (parameter) {
				case GenericLifetimeParam(name, bounds):
					if (name == null || bounds == null)
						throw "Rust lifetime parameter requires a name and bounds list";
					for (bound in bounds) {
						if (bound == null)
							throw "Rust lifetime parameter bound cannot be null";
					}
					if (sawTypeOrConst)
						throw "Rust lifetime parameters must precede type and const parameters";
					if (lifetimeNames.exists(name.name))
						throw 'Duplicate Rust lifetime parameter `${name.name}`';
					lifetimeNames.set(name.name, true);
				case GenericTypeParam(name, bounds, _):
					if (name == null || bounds == null)
						throw "Rust type parameter requires a name and bounds list";
					for (bound in bounds) {
						if (bound == null)
							throw "Rust type parameter bound cannot be null";
						switch (bound) {
							case GenericTraitBound(path, modifier):
								if (path == null || modifier == null)
									throw "Rust trait bound requires a path and modifier";
							case GenericLifetimeBound(lifetime):
								if (lifetime == null)
									throw "Rust lifetime bound cannot be null";
						}
					}
					sawTypeOrConst = true;
					if (valueNames.exists(name.name))
						throw 'Duplicate Rust generic parameter `${name.name}`';
					valueNames.set(name.name, true);
				case GenericConstParam(name, type, _):
					if (name == null || type == null)
						throw "Rust const parameter requires a name and type";
					sawTypeOrConst = true;
					if (valueNames.exists(name.name))
						throw 'Duplicate Rust generic parameter `${name.name}`';
					valueNames.set(name.name, true);
			}
		}
		return new RustGenericParameters(copy);
	}

	public static function empty():RustGenericParameters {
		return new RustGenericParameters([]);
	}

	function get_count():Int {
		return parameters.length;
	}

	public function at(index:Int):RustGenericParameter {
		return parameters[index];
	}

	public function iterator():Iterator<RustGenericParameter> {
		return parameters.iterator();
	}
}

/** Distinguishes ordinary, angle-generic, and function-trait path segments. */
enum RustPathSegmentArgumentStyle {
	PathArgumentsNone;
	PathArgumentsAngle;
	PathArgumentsParenthesized;
}

/**
	One validated segment of a structural Rust path.

	Why
	- Generic arguments belong to a particular segment (`Array<T>::Item`), and expression paths need
	  turbofish punctuation (`Array::<T>::new`) while type paths do not.

	What
	- Couples one `RustIdentifier` with either no arguments, typed angle arguments, or typed
	  parenthesized function-trait inputs and output.

	How
	- Use `plain`, `angle`, or `parenthesized`; every factory copies its input arrays.
	- The printer selects type-path versus expression-path punctuation from context.
**/
class RustPathSegment {
	public final identifier:RustIdentifier;
	public final argumentStyle:RustPathSegmentArgumentStyle;
	public final outputType:Null<RustType>;
	final angleArguments:Array<RustGenericArgument>;
	final inputTypes:Array<RustType>;
	public var genericArgumentCount(get, never):Int;
	public var inputTypeCount(get, never):Int;

	private function new(identifier:RustIdentifier, argumentStyle:RustPathSegmentArgumentStyle, angleArguments:Array<RustGenericArgument>,
		inputTypes:Array<RustType>, outputType:Null<RustType>) {
		if (identifier == null)
			throw "Rust path segment identifier cannot be null";
		this.identifier = identifier;
		this.argumentStyle = argumentStyle;
		this.angleArguments = angleArguments.copy();
		this.inputTypes = inputTypes.copy();
		this.outputType = outputType;
	}

	public static function plain(name:String):RustPathSegment {
		return plainIdentifier(RustIdentifier.named(name));
	}

	public static function plainIdentifier(identifier:RustIdentifier):RustPathSegment {
		return new RustPathSegment(identifier, PathArgumentsNone, [], [], null);
	}

	public static function angle(name:String, arguments:Array<RustGenericArgument>):RustPathSegment {
		return angleIdentifier(RustIdentifier.named(name), arguments);
	}

	public static function angleIdentifier(identifier:RustIdentifier, arguments:Array<RustGenericArgument>):RustPathSegment {
		if (arguments == null || arguments.length == 0)
			throw "Rust angle argument list cannot be empty";
		for (argument in arguments) {
			if (argument == null)
				throw "Rust generic argument cannot be null";
			switch (argument) {
				case GenericType(type):
					if (type == null)
						throw "Rust generic type argument cannot be null";
				case GenericConst(value):
					if (value == null)
						throw "Rust generic const argument cannot be null";
				case GenericLifetime(lifetime):
					if (lifetime == null)
						throw "Rust generic lifetime argument cannot be null";
			}
		}
		return new RustPathSegment(identifier, PathArgumentsAngle, arguments, [], null);
	}

	public static function parenthesized(name:String, inputs:Array<RustType>, output:Null<RustType>):RustPathSegment {
		if (inputs == null)
			throw "Rust parenthesized path inputs cannot be null";
		for (input in inputs) {
			if (input == null)
				throw "Rust parenthesized path input cannot be null";
		}
		return new RustPathSegment(RustIdentifier.named(name), PathArgumentsParenthesized, [], inputs, output);
	}

	function get_genericArgumentCount():Int {
		return angleArguments.length;
	}

	function get_inputTypeCount():Int {
		return inputTypes.length;
	}

	public function genericArgumentAt(index:Int):RustGenericArgument {
		return angleArguments[index];
	}

	public function inputTypeAt(index:Int):RustType {
		return inputTypes[index];
	}
}

/** The closed roots supported by a structural Rust path. */
enum RustPathRoot {
	PathRelative;
	PathAbsolute;
	PathCrate;
	PathSelfModule;
	PathSuper(depth:Int);
	PathTypeSelf;
	PathQualified(selfType:RustType, traitPath:Null<RustPath>);
}

/**
	A structural Rust path with a closed root and validated segments.

	Why
	- Paths drive ownership checks, runtime policy, type identity, and diagnostics. Treating
	  `crate::HxRef<T>` as an opaque string forces semantic passes to parse printer output.

	What
	- Represents relative, absolute, crate, module-self, super, type-`Self`, and qualified associated
	  paths such as `<T as Iterator>::Item`.
	- Each segment owns typed generic arguments; no factory accepts a complete rendered path.

	How
	- Select the root-specific factory and supply validated segments.
	- `single` is the convenience boundary for one compiler-known identifier, not a path parser.
	- Traversal uses `segmentCount`, `segmentAt`, and `iterator`; append returns a new path.
**/
class RustPath {
	public final root:RustPathRoot;
	final segments:Array<RustPathSegment>;
	public var segmentCount(get, never):Int;

	private function new(root:RustPathRoot, segments:Array<RustPathSegment>) {
		this.root = root;
		this.segments = validateSegments(segments);
	}

	public static function single(name:String):RustPath {
		return relative([RustPathSegment.plain(name)]);
	}

	public static function relative(segments:Array<RustPathSegment>):RustPath {
		if (segments == null || segments.length == 0)
			throw "Relative Rust path requires at least one segment";
		return new RustPath(PathRelative, segments);
	}

	public static function absolute(segments:Array<RustPathSegment>):RustPath {
		if (segments == null || segments.length == 0)
			throw "Absolute Rust path requires at least one segment";
		return new RustPath(PathAbsolute, segments);
	}

	public static function cratePath(segments:Array<RustPathSegment>):RustPath {
		if (segments == null || segments.length == 0)
			throw "Rust crate path requires at least one segment";
		return new RustPath(PathCrate, segments);
	}

	public static function selfModule(segments:Array<RustPathSegment>):RustPath {
		if (segments == null || segments.length == 0)
			throw "Rust module-self path requires at least one segment";
		return new RustPath(PathSelfModule, segments);
	}

	public static function superPath(depth:Int, segments:Array<RustPathSegment>):RustPath {
		if (depth < 1)
			throw "Rust super path depth must be at least one";
		if (segments == null || segments.length == 0)
			throw "Rust super path requires at least one segment";
		return new RustPath(PathSuper(depth), segments);
	}

	public static function typeSelf(segments:Array<RustPathSegment>):RustPath {
		return new RustPath(PathTypeSelf, segments);
	}

	public static function qualified(selfType:RustType, traitPath:Null<RustPath>, segments:Array<RustPathSegment>):RustPath {
		if (selfType == null)
			throw "Qualified Rust path requires a self type";
		if (segments == null || segments.length == 0)
			throw "Qualified Rust path requires an associated segment";
		return new RustPath(PathQualified(selfType, traitPath), segments);
	}

	function get_segmentCount():Int {
		return segments.length;
	}

	public function segmentAt(index:Int):RustPathSegment {
		return segments[index];
	}

	public function iterator():Iterator<RustPathSegment> {
		return segments.iterator();
	}

	public function append(segment:RustPathSegment):RustPath {
		if (segment == null)
			throw "Appended Rust path segment cannot be null";
		var next = segments.copy();
		next.push(segment);
		return new RustPath(root, next);
	}

	public function isRelative():Bool {
		return root == PathRelative;
	}

	public function firstIdentifierName():Null<String> {
		return segments.length == 0 ? null : segments[0].identifier.name;
	}

	static function validateSegments(values:Array<RustPathSegment>):Array<RustPathSegment> {
		if (values == null)
			throw "Rust path segments cannot be null";
		var copy = values.copy();
		for (segment in copy) {
			if (segment == null)
				throw "Rust path segment cannot be null";
		}
		return copy;
	}
}

enum RustVisibility {
	VPrivate;
	VPub;
	VPubCrate;
}

typedef RustFile = {
	var items:Array<RustItem>;
}

enum RustItem {
	RFn(f:RustFunction);
	RStruct(s:RustStruct);
	REnum(e:RustEnum);
	RImpl(i:RustImpl);
	RRaw(fragment:RustRawCode);
}

typedef RustStruct = {
	var name:String;
	var isPub:Bool;
	@:optional var vis:RustVisibility;
	@:optional var generics:Array<String>;
	var fields:Array<RustStructField>;
}

typedef RustStructField = {
	var name:String;
	var ty:RustType;
	var isPub:Bool;
	@:optional var vis:RustVisibility;
}

typedef RustEnum = {
	var name:String;
	var isPub:Bool;
	@:optional var vis:RustVisibility;
	@:optional var generics:Array<String>;
	var derives:Array<String>;
	var variants:Array<RustEnumVariant>;
}

typedef RustEnumVariant = {
	var name:String;
	var args:Array<RustType>;
}

typedef RustImpl = {
	@:optional var generics:Array<String>;
	var forType:String;
	var functions:Array<RustFunction>;
}

typedef RustFunction = {
	var name:String;
	var isPub:Bool;
	@:optional var vis:RustVisibility;
	@:optional var isAsync:Bool;
	@:optional var generics:Array<String>;
	var args:Array<RustFnArg>;
	var ret:RustType;
	var body:RustBlock;
}

typedef RustFnArg = {
	var name:String;
	var ty:RustType;
}

enum RustType {
	RUnit;
	RBool;
	RI32;
	RF64;
	RString;
	// Legacy string-backed reference and path nodes remain only until haxe.rust-oo3.98.2.2.2
	// migrates their production constructors. New typed IR must use the structural alternatives.
	RRef(inner:RustType, mutable:Bool);
	RPath(path:String);
	RNamed(path:RustPath);
	RBorrow(inner:RustType, mutable:Bool, lifetime:Null<RustLifetime>);
	RTuple(elements:Array<RustType>);
	RSlice(element:RustType);
	RArray(element:RustType, length:RustConstArgument);
}

typedef RustBlock = {
	var stmts:Array<RustStmt>;
	var tail:Null<RustExpr>;
}

typedef RustMatchArm = {
	var pat:RustPattern;
	var expr:RustExpr;
}

typedef RustStructLitField = {
	var name:String;
	var expr:RustExpr;
}

enum RustPattern {
	PWildcard;
	PBind(name:String);
	PAlias(name:String, pattern:RustPattern);
	PPath(path:String);
	PLitInt(v:Int);
	PLitBool(v:Bool);
	PLitString(v:String);
	PTupleStruct(path:String, fields:Array<RustPattern>);
	POr(patterns:Array<RustPattern>);
}

enum RustStmt {
	RLet(name:String, mutable:Bool, ty:Null<RustType>, expr:Null<RustExpr>);
	RSemi(e:RustExpr);
	// Like `RSemi`, but allows emitting statement-like expressions without a trailing semicolon
	// (e.g. unit-typed `if` / `match` / `{ ... }` blocks).
	RExpr(e:RustExpr, needsSemicolon:Bool);
	RReturn(e:Null<RustExpr>);
	RWhile(cond:RustExpr, body:RustBlock);
	RLoop(body:RustBlock);
	RFor(name:String, iter:RustExpr, body:RustBlock);
	RBreak;
	RContinue;
}

enum RustExpr {
	ERaw(fragment:RustRawCode);
	ELitInt(v:Int);
	ELitFloat(v:Float);
	ELitBool(v:Bool);
	ELitString(v:String);
	EPath(path:String);
	ECall(func:RustExpr, args:Array<RustExpr>);
	EMacroCall(name:String, args:Array<RustExpr>);
	EClosure(args:Array<String>, body:RustBlock, isMove:Bool);
	EBinary(op:String, left:RustExpr, right:RustExpr);
	EUnary(op:String, expr:RustExpr);
	ERange(start:RustExpr, end:RustExpr);
	ECast(expr:RustExpr, ty:String);
	EIndex(recv:RustExpr, index:RustExpr);
	EStructLit(path:String, fields:Array<RustStructLitField>);
	EBlock(b:RustBlock);
	EIf(cond:RustExpr, thenExpr:RustExpr, elseExpr:Null<RustExpr>);
	EMatch(scrutinee:RustExpr, arms:Array<RustMatchArm>);
	EAssign(lhs:RustExpr, rhs:RustExpr);
	EField(recv:RustExpr, field:String);
	// Typed async wrapper used for `@:rustAsync` lowering.
	//
	// Why
	// - The compiler historically emitted this shape as `ERaw("Box::pin(async move { ... })")`,
	//   which inflated metal fallback diagnostics even though the structure is compiler-owned and
	//   deterministic.
	//
	// What
	// - Represents `Box::pin(async move { <body> })` with a typed `RustBlock` payload.
	//
	// How
	// - Printer renders this constructor directly; traversal passes recurse into `body`.
	EPinAsyncMove(body:RustBlock);
	EAwait(expr:RustExpr);
}
