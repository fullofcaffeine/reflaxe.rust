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
	RawStaticStorage;
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
					case RawStaticStorage: "static-storage";
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
	- Covers signed decimal integer literals, booleans, and structural const paths, which are the closed
	  forms needed by the current compiler roadmap.

	How
	- Use the validating factories below. More complex const expressions must gain a typed AST node;
	  callers must not smuggle them through a string fallback.
**/
class RustConstArgument {
	public final kind:RustConstArgumentKind;
	public final integerDigits:Null<String>;
	public final integerNegative:Bool;
	public final boolValue:Null<Bool>;
	public final pathValue:Null<RustPath>;

	private function new(kind:RustConstArgumentKind, integerDigits:Null<String>, integerNegative:Bool, boolValue:Null<Bool>,
			pathValue:Null<RustPath>) {
		this.kind = kind;
		this.integerDigits = integerDigits;
		this.integerNegative = integerNegative;
		this.boolValue = boolValue;
		this.pathValue = pathValue;
	}

	public static function integer(value:Int):RustConstArgument {
		return decimalSignedInteger(Std.string(value));
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
		return decimalSignedInteger(digits);
	}

	/**
		Constructs an arbitrarily wide signed decimal const integer.

		Why / What / How
		- Rust marker-trait paths may use signed const arguments such as `Marker<-1>`.
		- Accepts an optional leading minus and decimal digits only, canonicalizes leading zeroes, and
		  normalizes negative zero to ordinary zero. The printer owns the minus token.
	**/
	public static function decimalSignedInteger(value:String):RustConstArgument {
		if (value == null || value.length == 0 || !~/^-?[0-9]+$/.match(value))
			throw 'Invalid Rust signed decimal const integer `$value`';
		var negative = StringTools.startsWith(value, "-");
		var digits = negative ? value.substr(1) : value;
		var firstNonZero = 0;
		while (firstNonZero < digits.length - 1 && digits.charAt(firstNonZero) == "0")
			firstNonZero++;
		var canonical = digits.substr(firstNonZero);
		return new RustConstArgument(ConstInteger, canonical, negative && canonical != "0", null, null);
	}

	public static function boolean(value:Bool):RustConstArgument {
		return new RustConstArgument(ConstBoolean, null, false, value, null);
	}

	public static function path(value:RustPath):RustConstArgument {
		if (value == null)
			throw "Rust const path cannot be null";
		return new RustConstArgument(ConstPath, null, false, null, value);
	}
}

/** A type, const, lifetime, or inference argument inside a Rust path segment's angle arguments. */
enum RustGenericArgument {
	GenericType(type:RustType);
	GenericConst(argument:RustConstArgument);
	GenericLifetime(lifetime:RustLifetime);
	/**
		Rust's inferred generic placeholder.

		Why
		- Expressions such as `collect::<Vec<_>>()` need inference without disguising `_` as a named type.

		What
		- Represents the closed Rust placeholder form independently from type, const, and lifetime values.

		How
		- Metadata/lowering select this constructor; the printer alone emits `_`.
	**/
	GenericInfer;
}

/**
	A closed structural Rust generic bound.

	Why
	- Rust's `?` is not a general "optional trait" modifier. `?Sized` only removes the implicit
	  `Sized` requirement in declaration contexts where Rust permits that relaxation.
	- Modeling `?Clone` and `?Sized` with one modifier lets invalid bounds leak into supertraits,
	  trait objects, and arbitrary where predicates.

	What
	- Separates ordinary required trait paths, the single relaxed-size state, and lifetime bounds.

	How
	- Use `GenericTraitBound` for every required trait and `GenericRelaxedSized` only for a generic type
	  parameter or associated-type declaration. Context-owning factories reject the relaxed state
	  everywhere else, and the printer alone emits `?Sized`.
**/
enum RustGenericBound {
	GenericTraitBound(path:RustPath);
	GenericRelaxedSized;
	GenericLifetimeBound(lifetime:RustLifetime);
}

/**
	Validates and owns generic-bound arrays for one exact Rust grammar context.

	Why / What / How
	- Several declarations share bound syntax but differ on whether they may relax implicit sizing.
	- `copyValidated` defensively owns the array, checks every payload, rejects contradictory
	  `Sized + ?Sized`, and requires the caller to state whether its declaration context admits
	  `GenericRelaxedSized`.
**/
private class RustGenericBoundSyntax {
	public static function copyValidated(values:Array<RustGenericBound>, label:String, allowRelaxedSized:Bool):Array<RustGenericBound> {
		if (values == null)
			throw '$label bounds cannot be null';
		var copy = values.copy();
		var sawRelaxedSized = false;
		var sawRequiredSized = false;
		for (bound in copy) {
			if (bound == null)
				throw '$label cannot contain a null bound';
			switch (bound) {
				case GenericTraitBound(path):
					if (path == null)
						throw '$label trait bound requires a path';
					if (path.plainRelativeIdentifierName() == "Sized")
						sawRequiredSized = true;
				case GenericRelaxedSized:
					if (!allowRelaxedSized)
						throw '$label cannot relax the implicit Sized bound';
					if (sawRelaxedSized)
						throw '$label cannot repeat the relaxed Sized bound';
					sawRelaxedSized = true;
				case GenericLifetimeBound(lifetime):
					if (lifetime == null)
						throw '$label lifetime bound cannot be null';
			}
		}
		if (sawRelaxedSized && sawRequiredSized)
			throw '$label cannot require and relax Sized at the same time';
		return copy;
	}
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
	- Construct with `of`; malformed order and duplicate names fail immediately at the AST boundary,
	  and nested lifetime/type-bound arrays are copied so callers cannot mutate an existing declaration.
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
		var copy:Array<RustGenericParameter> = [];
		var sawTypeOrConst = false;
		var lifetimeNames:Map<String, Bool> = [];
		var valueNames:Map<String, Bool> = [];
		for (parameter in values) {
			if (parameter == null)
				throw "Rust generic parameter cannot be null";
			switch (parameter) {
				case GenericLifetimeParam(name, bounds):
					if (name == null || bounds == null)
						throw "Rust lifetime parameter requires a name and bounds list";
					var ownedBounds = bounds.copy();
					for (bound in ownedBounds) {
						if (bound == null)
							throw "Rust lifetime parameter bound cannot be null";
					}
					if (sawTypeOrConst)
						throw "Rust lifetime parameters must precede type and const parameters";
					if (lifetimeNames.exists(name.name))
						throw 'Duplicate Rust lifetime parameter `${name.name}`';
					lifetimeNames.set(name.name, true);
					copy.push(GenericLifetimeParam(name, ownedBounds));
				case GenericTypeParam(name, bounds, defaultType):
					if (name == null || bounds == null)
						throw "Rust type parameter requires a name and bounds list";
					var ownedBounds = RustGenericBoundSyntax.copyValidated(bounds, "Rust type parameter", true);
					sawTypeOrConst = true;
					if (valueNames.exists(name.name))
						throw 'Duplicate Rust generic parameter `${name.name}`';
					valueNames.set(name.name, true);
					copy.push(GenericTypeParam(name, ownedBounds, defaultType));
				case GenericConstParam(name, type, defaultValue):
					if (name == null || type == null)
						throw "Rust const parameter requires a name and type";
					sawTypeOrConst = true;
					if (valueNames.exists(name.name))
						throw 'Duplicate Rust generic parameter `${name.name}`';
					valueNames.set(name.name, true);
					copy.push(GenericConstParam(name, type, defaultValue));
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

/**
	A validated structural Rust trait object (`dyn Trait + Send + 'a`).

	Why
	- Function values, interfaces, and polymorphic classes use trait objects in generated Rust.
	- Hiding `dyn`, auto-trait bounds, or lifetimes inside `RPath(String)` prevents ownership and
	  thread-safety passes from inspecting the actual contract.

	What
	- Owns a non-empty, defensively copied list of required trait and lifetime bounds.
	- Rejects relaxed `?Trait` bounds because Rust does not admit them in trait-object syntax.

	How
	- Build paths (including parenthesized `Fn(...) -> ...`) structurally, wrap them in
	  `RustGenericBound`, then call `of`.
	- `RTraitObject` stores this value; the printer alone emits `dyn` and `+` punctuation.
**/
class RustTraitObject {
	final bounds:Array<RustGenericBound>;
	public var count(get, never):Int;

	private function new(bounds:Array<RustGenericBound>) {
		this.bounds = bounds;
	}

	public static function of(values:Array<RustGenericBound>):RustTraitObject {
		if (values == null || values.length == 0)
			throw "Rust trait object requires at least one bound";
		var copy = RustGenericBoundSyntax.copyValidated(values, "Rust trait object", false);
		var hasTrait = false;
		for (bound in copy) {
			switch (bound) {
				case GenericTraitBound(_):
					hasTrait = true;
				case GenericRelaxedSized | GenericLifetimeBound(_):
			}
		}
		if (!hasTrait)
			throw "Rust trait object requires at least one trait bound";
		return new RustTraitObject(copy);
	}

	function get_count():Int {
		return bounds.length;
	}

	public function at(index:Int):RustGenericBound {
		return bounds[index];
	}

	public function iterator():Iterator<RustGenericBound> {
		return bounds.iterator();
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
				case GenericInfer:
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

/**
	A validated Rust receiver member with optional structural generic arguments.

	Why
	- Method and field access used to store the complete suffix as `String`, allowing target syntax
	  such as `downcast_ref::<T>` to bypass path traversal and runtime-policy analysis.
	- A receiver member is narrower than a general path segment: Rust does not permit the
	  parenthesized function-trait form after `receiver.`.

	What
	- Wraps exactly one plain or angle-generic `RustPathSegment` and exposes its identifier and generic
	  arguments without exposing printer punctuation.
	- Construction defensively inherits the segment's copied generic-argument storage.

	How
	- Use `plain` for ordinary fields/methods and `generic` for method turbofish arguments.
	- Use the identifier factories only when the caller already owns a validated raw identifier.
	- The expression printer alone decides that angle arguments after a receiver require `::<...>`.
**/
class RustMember {
	final segment:RustPathSegment;
	public var identifier(get, never):RustIdentifier;
	public var genericArgumentCount(get, never):Int;

	private function new(segment:RustPathSegment) {
		if (segment == null)
			throw "Rust receiver member cannot be null";
		if (segment.argumentStyle == PathArgumentsParenthesized)
			throw "Rust receiver members cannot use parenthesized path arguments";
		this.segment = segment;
	}

	public static function plain(name:String):RustMember {
		return plainIdentifier(RustIdentifier.named(name));
	}

	public static function plainIdentifier(identifier:RustIdentifier):RustMember {
		return new RustMember(RustPathSegment.plainIdentifier(identifier));
	}

	public static function generic(name:String, arguments:Array<RustGenericArgument>):RustMember {
		return genericIdentifier(RustIdentifier.named(name), arguments);
	}

	public static function genericIdentifier(identifier:RustIdentifier, arguments:Array<RustGenericArgument>):RustMember {
		return new RustMember(RustPathSegment.angleIdentifier(identifier, arguments));
	}

	function get_identifier():RustIdentifier {
		return segment.identifier;
	}

	function get_genericArgumentCount():Int {
		return segment.genericArgumentCount;
	}

	public function genericArgumentAt(index:Int):RustGenericArgument {
		return segment.genericArgumentAt(index);
	}

	public function isPlain():Bool {
		return segment.argumentStyle == PathArgumentsNone;
	}

	public function asPathSegment():RustPathSegment {
		return segment;
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

	/**
		Returns the identifier carried by a plain one-segment relative path.

		Why
		- Ownership and cleanup passes must distinguish a local binding read from a qualified target
		  path without parsing `::` delimiters from printer output.

		What
		- Admits only `PathRelative` with exactly one argument-free segment.
		- Returns `null` for qualified, rooted, multi-segment, generic, or function-trait paths.

		How
		- Compare the returned name with a known binding table; a one-segment path is syntactically
		  local-shaped but only the owning analysis knows whether that identifier is a binding.
	**/
	public function plainRelativeIdentifierName():Null<String> {
		if (!isRelative() || segments.length != 1)
			return null;
		var segment = segments[0];
		return segment.argumentStyle == PathArgumentsNone ? segment.identifier.name : null;
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
	RAttributed(value:RustAttributedItem);
	RInnerAttribute(attribute:RustAttribute);
	RComment(comment:RustComment);
	RUse(declaration:RustUseDeclaration);
	RModule(declaration:RustModuleDeclaration);
	RConst(declaration:RustConstantDeclaration);
	RStatic(declaration:RustStaticDeclaration);
	RTypeAlias(declaration:RustTypeAliasDeclaration);
	RFn(f:RustFunction);
	RStruct(s:RustStruct);
	REnum(e:RustEnum);
	RTrait(declaration:RustTraitDeclaration);
	RImpl(i:RustImpl);
	RRaw(fragment:RustRawCode);
}

/** Identifies the closed payload form carried by one structural Rust attribute. */
enum RustAttributeInputKind {
	AttributeBare;
	AttributePathList;
	AttributeStringValue;
}

/**
	A structural Rust attribute without its outer/inner attachment punctuation.

	Why
	- Attribute paths and arguments participate in name resolution and no-runtime policy. A rendered
	  string such as `#[derive(Clone)]` hides both from analysis and can be detached from its target.
	- Metadata-backed derive paths are a legitimate input boundary, but they must become structural
	  immediately instead of remaining target text throughout lowering.

	What
	- Represents a bare attribute, a non-empty list of simple-path arguments, or a string value.
	- Stores only relative, argument-free paths; generic/function/qualified syntax is rejected.

	How
	- Use `bare`, `pathList`, or `stringValue`, then attach outer attributes with
	  `RustAttributedItem.of` or emit an enclosing-item attribute with `RInnerAttribute`.
	- The printer owns `#`, `!`, brackets, parentheses, commas, `=`, and string escaping.
**/
class RustAttribute {
	public final path:RustPath;
	public final inputKind:RustAttributeInputKind;
	final arguments:Array<RustPath>;
	public final stringPayload:Null<String>;
	public var argumentCount(get, never):Int;

	private function new(path:RustPath, inputKind:RustAttributeInputKind, arguments:Array<RustPath>, stringPayload:Null<String>) {
		this.path = RustItemSyntax.requireSimpleRelativePath(path, "Rust attribute path");
		this.inputKind = inputKind;
		this.arguments = arguments;
		this.stringPayload = stringPayload;
	}

	public static function bare(path:RustPath):RustAttribute {
		return new RustAttribute(path, AttributeBare, [], null);
	}

	public static function pathList(path:RustPath, arguments:Array<RustPath>):RustAttribute {
		if (arguments == null || arguments.length == 0)
			throw "Rust attribute path list requires at least one argument";
		var copy = arguments.copy();
		for (argument in copy)
			RustItemSyntax.requireSimpleRelativePath(argument, "Rust attribute argument");
		return new RustAttribute(path, AttributePathList, copy, null);
	}

	public static function stringValue(path:RustPath, value:String):RustAttribute {
		if (value == null)
			throw "Rust attribute string value cannot be null";
		return new RustAttribute(path, AttributeStringValue, [], value);
	}

	function get_argumentCount():Int {
		return arguments.length;
	}

	public function argumentAt(index:Int):RustPath {
		if (index < 0 || index >= arguments.length)
			throw 'Rust attribute argument index out of bounds: $index';
		return arguments[index];
	}

	public function iterator():Iterator<RustPath> {
		return arguments.iterator();
	}
}

/**
	A non-empty outer-attribute list attached to exactly one Rust item.

	Why
	- Free-standing outer attributes can silently retarget after a pass inserts, removes, or reorders
	  items. Attribute ownership must survive transformation as part of the same node.

	What
	- Owns a defensive copy of one or more attributes and one non-annotation target item.
	- Rejects nested wrappers, inner attributes, and comments as targets so attachment is unambiguous.

	How
	- Construct with `of`; recursive passes must transform `target` while retaining the attributes.
	- Inner crate/module attributes remain explicit `RInnerAttribute` items because their target is the
	  enclosing item rather than the following declaration.
**/
class RustAttributedItem {
	final attributes:Array<RustAttribute>;
	public final target:RustItem;
	public var attributeCount(get, never):Int;

	private function new(attributes:Array<RustAttribute>, target:RustItem) {
		this.attributes = attributes;
		this.target = target;
	}

	public static function of(attributes:Array<RustAttribute>, target:RustItem):RustAttributedItem {
		if (attributes == null || attributes.length == 0)
			throw "Rust attributed item requires at least one outer attribute";
		var copy = attributes.copy();
		for (attribute in copy) {
			if (attribute == null)
				throw "Rust outer attribute cannot be null";
		}
		if (target == null)
			throw "Rust attributed item target cannot be null";
		switch (target) {
			case RAttributed(_) | RInnerAttribute(_) | RComment(_):
				throw "Rust outer attributes require one concrete declaration target";
			case _:
		}
		return new RustAttributedItem(copy, target);
	}

	function get_attributeCount():Int {
		return attributes.length;
	}

	public function attributeAt(index:Int):RustAttribute {
		if (index < 0 || index >= attributes.length)
			throw 'Rust outer attribute index out of bounds: $index';
		return attributes[index];
	}

	public function iterator():Iterator<RustAttribute> {
		return attributes.iterator();
	}

	public function withTarget(next:RustItem):RustAttributedItem {
		return of(attributes, next);
	}
}

/**
	One generated Rust line comment stored without target punctuation.

	Why
	- Generated markers are compiler-owned declarations of provenance, not raw Rust authority.
	- Allowing embedded newlines would let one comment node smuggle arbitrary target items.

	What
	- Stores one line of comment text, including the empty line when needed.

	How
	- `line` rejects carriage returns and line feeds; the printer owns the `//` prefix.
**/
class RustComment {
	public final text:String;

	private function new(text:String) {
		this.text = text;
	}

	public static function line(text:String):RustComment {
		if (text == null)
			throw "Rust line comment cannot be null";
		if (text.indexOf("\n") != -1 || text.indexOf("\r") != -1)
			throw "Rust line comment cannot contain a line delimiter";
		return new RustComment(text);
	}

	public static function generatedFileMarker():RustComment {
		return line("Generated by reflaxe.rust");
	}
}

/** Identifies one relative member of a structural grouped Rust use declaration. */
enum RustUseMemberKind {
	UseMemberPath;
	UseMemberSelf;
	UseMemberGlob;
}

/**
	One member inside a grouped Rust `use` tree.

	Why / What / How
	- Group punctuation, aliases, `self`, and globs must remain distinguishable without parsing text.
	- `path` accepts only an argument-free relative path and validates an optional alias identifier.
	- `selfImport` and `glob` represent the two keyword members without pretending they are paths.
**/
class RustUseMember {
	public final kind:RustUseMemberKind;
	public final pathValue:Null<RustPath>;
	public final alias:Null<RustIdentifier>;

	private function new(kind:RustUseMemberKind, pathValue:Null<RustPath>, alias:Null<RustIdentifier>) {
		this.kind = kind;
		this.pathValue = pathValue;
		this.alias = alias;
	}

	public static function path(path:RustPath, ?alias:String):RustUseMember {
		return new RustUseMember(UseMemberPath, RustItemSyntax.requireSimpleRelativePath(path, "Rust grouped-use member"),
			alias == null ? null : RustIdentifier.named(alias));
	}

	public static function selfImport(?alias:String):RustUseMember {
		return new RustUseMember(UseMemberSelf, null, alias == null ? null : RustIdentifier.named(alias));
	}

	public static function glob():RustUseMember {
		return new RustUseMember(UseMemberGlob, null, null);
	}
}

/** Identifies the closed shape of one structural Rust use declaration. */
enum RustUseKind {
	UseExact;
	UseGlob;
	UseGroup;
}

/**
	A structural Rust `use` declaration.

	Why
	- Imports affect trait method resolution and runtime namespace policy. Rendered `use` strings hide
	  roots, group entries, aliases, and glob authority from compiler analysis.

	What
	- Represents an exact optional-rename import, a prefix glob, or a non-empty grouped import.
	- Uses one explicit `RustVisibility`; no legacy boolean visibility is retained.

	How
	- Construct with `exact`, `glob`, or `group`. Paths are validated as argument-free use paths and
	  group arrays are defensively copied. The printer owns every delimiter and keyword.
**/
class RustUseDeclaration {
	public final visibility:RustVisibility;
	public final kind:RustUseKind;
	public final prefix:RustPath;
	public final alias:Null<RustIdentifier>;
	final members:Array<RustUseMember>;
	public var memberCount(get, never):Int;

	private function new(visibility:RustVisibility, kind:RustUseKind, prefix:RustPath, alias:Null<RustIdentifier>, members:Array<RustUseMember>) {
		if (visibility == null)
			throw "Rust use visibility cannot be null";
		this.visibility = visibility;
		this.kind = kind;
		this.prefix = RustItemSyntax.requireUsePath(prefix, "Rust use path");
		this.alias = alias;
		this.members = members;
	}

	public static function exact(visibility:RustVisibility, path:RustPath, ?alias:String):RustUseDeclaration {
		return new RustUseDeclaration(visibility, UseExact, path, alias == null ? null : RustIdentifier.named(alias), []);
	}

	public static function glob(visibility:RustVisibility, prefix:RustPath):RustUseDeclaration {
		return new RustUseDeclaration(visibility, UseGlob, prefix, null, []);
	}

	public static function group(visibility:RustVisibility, prefix:RustPath, members:Array<RustUseMember>):RustUseDeclaration {
		if (members == null || members.length == 0)
			throw "Rust grouped use requires at least one member";
		var copy = members.copy();
		for (member in copy) {
			if (member == null)
				throw "Rust grouped-use member cannot be null";
		}
		return new RustUseDeclaration(visibility, UseGroup, prefix, null, copy);
	}

	function get_memberCount():Int {
		return members.length;
	}

	public function memberAt(index:Int):RustUseMember {
		if (index < 0 || index >= members.length)
			throw 'Rust grouped-use member index out of bounds: $index';
		return members[index];
	}

	public function iterator():Iterator<RustUseMember> {
		return members.iterator();
	}
}

/**
	An external or recursively inline Rust module declaration.

	Why
	- `mod child;` and `mod child { }` have different filesystem and ownership semantics; null/empty
	  arrays must not blur that distinction.

	What
	- Stores a validated module identifier, explicit visibility, and either external or inline shape.
	- Inline children are defensively copied and exposed through bounded accessors.

	How
	- Use `external` for file-backed modules and `inlineModule` for an inline body, including an empty
	  body. Recursive passes rebuild inline nodes with `withItems`.
**/
class RustModuleDeclaration {
	public final visibility:RustVisibility;
	public final name:RustIdentifier;
	public final isInline:Bool;
	final items:Array<RustItem>;
	public var itemCount(get, never):Int;

	private function new(visibility:RustVisibility, name:String, isInline:Bool, items:Array<RustItem>) {
		if (visibility == null)
			throw "Rust module visibility cannot be null";
		this.visibility = visibility;
		this.name = RustIdentifier.named(name);
		this.isInline = isInline;
		this.items = items;
	}

	public static function external(visibility:RustVisibility, name:String):RustModuleDeclaration {
		return new RustModuleDeclaration(visibility, name, false, []);
	}

	public static function inlineModule(visibility:RustVisibility, name:String, items:Array<RustItem>):RustModuleDeclaration {
		if (items == null)
			throw "Rust inline module items cannot be null";
		var copy = items.copy();
		for (item in copy) {
			if (item == null)
				throw "Rust inline module item cannot be null";
		}
		return new RustModuleDeclaration(visibility, name, true, copy);
	}

	function get_itemCount():Int {
		return items.length;
	}

	public function itemAt(index:Int):RustItem {
		if (index < 0 || index >= items.length)
			throw 'Rust module item index out of bounds: $index';
		return items[index];
	}

	public function iterator():Iterator<RustItem> {
		return items.iterator();
	}

	public function withItems(next:Array<RustItem>):RustModuleDeclaration {
		if (!isInline)
			throw "External Rust module cannot acquire inline items";
		return inlineModule(visibility, name.name, next);
	}
}

/** A typed Rust constant declaration with a structural type and initializer expression. */
class RustConstantDeclaration {
	public final visibility:RustVisibility;
	public final name:RustIdentifier;
	public final type:RustType;
	public final value:RustExpr;

	private function new(visibility:RustVisibility, name:String, type:RustType, value:RustExpr) {
		if (visibility == null || type == null || value == null)
			throw "Rust constant requires visibility, type, and initializer";
		this.visibility = visibility;
		this.name = RustIdentifier.named(name);
		this.type = type;
		this.value = value;
	}

	public static function named(visibility:RustVisibility, name:String, type:RustType, value:RustExpr):RustConstantDeclaration {
		return new RustConstantDeclaration(visibility, name, type, value);
	}

	public function withValue(next:RustExpr):RustConstantDeclaration {
		return named(visibility, name.name, type, next);
	}
}

/**
	A typed module-scope Rust static declaration.

	Why / What / How
	- Generated test synchronization needs a stable process-wide cell, which is runtime state rather
	  than a `const`; representing it structurally avoids retaining an otherwise fully raw test module.
	- Stores explicit visibility, validated name, type, and initializer. Use `withValue` from mappers.
**/
class RustStaticDeclaration {
	public final visibility:RustVisibility;
	public final name:RustIdentifier;
	public final type:RustType;
	public final value:RustExpr;

	private function new(visibility:RustVisibility, name:String, type:RustType, value:RustExpr) {
		if (visibility == null || type == null || value == null)
			throw "Rust static requires visibility, type, and initializer";
		this.visibility = visibility;
		this.name = RustIdentifier.named(name);
		this.type = type;
		this.value = value;
	}

	public static function named(visibility:RustVisibility, name:String, type:RustType, value:RustExpr):RustStaticDeclaration {
		return new RustStaticDeclaration(visibility, name, type, value);
	}

	public function withValue(next:RustExpr):RustStaticDeclaration {
		return named(visibility, name.name, type, next);
	}
}

/**
	A structural Rust type alias declaration.

	Why / What / How
	- Crate prelude aliases are compiler-owned item syntax and cannot stay inside a mixed raw header if
	  modules and attributes are to be structurally complete. This node reuses typed generic parameters
	  and `RustType`, validates its identifier/visibility, and lets the printer own `type`, `=`, and `;`.
**/
class RustTypeAliasDeclaration {
	public final visibility:RustVisibility;
	public final name:RustIdentifier;
	public final generics:RustGenericParameters;
	public final type:RustType;

	private function new(visibility:RustVisibility, name:String, generics:RustGenericParameters, type:RustType) {
		if (visibility == null || generics == null || type == null)
			throw "Rust type alias requires visibility, generics, and target type";
		this.visibility = visibility;
		this.name = RustIdentifier.named(name);
		this.generics = generics;
		this.type = type;
	}

	public static function named(visibility:RustVisibility, name:String, generics:RustGenericParameters, type:RustType):RustTypeAliasDeclaration {
		return new RustTypeAliasDeclaration(visibility, name, generics, type);
	}
}

private class RustItemSyntax {
	public static function requireSimpleRelativePath(path:RustPath, label:String):RustPath {
		if (path == null || !path.isRelative())
			throw '$label must be a relative simple path';
		return requireArgumentFree(path, label);
	}

	public static function requireUsePath(path:RustPath, label:String):RustPath {
		if (path == null)
			throw '$label cannot be null';
		switch (path.root) {
			case PathQualified(_, _):
				throw '$label cannot use a qualified type root';
			case PathTypeSelf:
				throw '$label cannot use the type-Self root';
			case _:
		}
		return requireArgumentFree(path, label);
	}

	static function requireArgumentFree(path:RustPath, label:String):RustPath {
		for (segment in path) {
			if (segment.argumentStyle != PathArgumentsNone)
				throw '$label cannot contain generic or function arguments';
		}
		return path;
	}
}

typedef RustStruct = {
	var name:String;
	var isPub:Bool;
	@:optional var vis:RustVisibility;
	var generics:RustGenericParameters;
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
	var generics:RustGenericParameters;
	var variants:Array<RustEnumVariant>;
}

typedef RustEnumVariant = {
	var name:String;
	var args:Array<RustType>;
}

/**
	The closed forms of a structural Rust `self` receiver.

	Why / What / How
	- `self`, `mut self`, `&self`, `&'a mut self`, `self: Type`, and `mut self: Type` have semantic ownership and
	  lifetime differences that cannot live in a parameter-name string.
	- Each constructor stores only the role-specific typed payload; an omitted borrowed lifetime means
	  Rust's ordinary elided receiver lifetime.
	- Put at most one receiver on `RustAssociatedFunction`; the printer owns every `&`, lifetime,
	  `mut`, `self`, and `:` token.
**/
enum RustSelfReceiver {
	ReceiverValue(mutable:Bool);
	ReceiverBorrowed(mutable:Bool, lifetime:Null<RustLifetime>);
	ReceiverTyped(type:RustType, mutable:Bool);
}

/**
	One validated named parameter on a structural associated function.

	Why / What / How
	- Associated methods need the same typed parameter visibility as ordinary functions, but their
	  receiver is modeled separately so `self` cannot be confused with a normal binding.
	- `named` validates the identifier immediately and requires a structural `RustType`; callers never
	  embed `name: Type` punctuation in either value.
**/
class RustFunctionParameter {
	public final name:RustIdentifier;
	public final type:RustType;

	private function new(name:String, type:RustType) {
		if (type == null)
			throw "Rust function parameter requires a type";
		this.name = RustIdentifier.named(name);
		this.type = type;
	}

	public static function named(name:String, type:RustType):RustFunctionParameter {
		return new RustFunctionParameter(name, type);
	}
}

/** Distinguishes the two stable predicate families represented by `RustWherePredicate`. */
enum RustWherePredicateKind {
	WhereTypeBounds;
	WhereLifetimeBounds;
}

/**
	One validated Rust where-clause predicate.

	Why
	- A rendered clause such as `T: Clone + 'a` hides which pieces are types, traits, and lifetimes.
	- Empty predicates are invalid Rust but are easy to create when bounds are assembled incrementally.

	What
	- Represents either a structural type with one or more generic bounds or a lifetime with one or
	  more outlives bounds.
	- Owns defensive copies so later source-array mutation cannot change declaration meaning.

	How
	- Construct with `typeBounds` or `lifetimeBounds`, then wrap one or more predicates in
	  `RustWhereClause.of`. The printer alone owns `where`, `:`, `+`, and comma punctuation.
**/
class RustWherePredicate {
	public final kind:RustWherePredicateKind;
	public final typeValue:Null<RustType>;
	public final lifetimeValue:Null<RustLifetime>;
	final genericBounds:Array<RustGenericBound>;
	final lifetimeBoundsValue:Array<RustLifetime>;
	public var boundCount(get, never):Int;

	private function new(kind:RustWherePredicateKind, typeValue:Null<RustType>, lifetimeValue:Null<RustLifetime>,
			genericBounds:Array<RustGenericBound>, lifetimeBoundsValue:Array<RustLifetime>) {
		this.kind = kind;
		this.typeValue = typeValue;
		this.lifetimeValue = lifetimeValue;
		this.genericBounds = genericBounds;
		this.lifetimeBoundsValue = lifetimeBoundsValue;
	}

	public static function typeBounds(type:RustType, bounds:Array<RustGenericBound>):RustWherePredicate {
		if (type == null)
			throw "Rust type where-predicate requires a type";
		var copy = validateGenericBounds(bounds, "Rust type where-predicate");
		if (copy.length == 0)
			throw "Rust type where-predicate requires at least one bound";
		return new RustWherePredicate(WhereTypeBounds, type, null, copy, []);
	}

	public static function lifetimeBounds(lifetime:RustLifetime, bounds:Array<RustLifetime>):RustWherePredicate {
		if (lifetime == null)
			throw "Rust lifetime where-predicate requires a lifetime";
		if (bounds == null || bounds.length == 0)
			throw "Rust lifetime where-predicate requires at least one bound";
		var copy = bounds.copy();
		for (bound in copy) {
			if (bound == null)
				throw "Rust lifetime where-predicate cannot contain a null bound";
		}
		return new RustWherePredicate(WhereLifetimeBounds, null, lifetime, [], copy);
	}

	public static function validateGenericBounds(bounds:Array<RustGenericBound>, label:String,
			?allowRelaxedSized:Bool = false):Array<RustGenericBound> {
		return RustGenericBoundSyntax.copyValidated(bounds, label, allowRelaxedSized);
	}

	function get_boundCount():Int {
		return kind == WhereTypeBounds ? genericBounds.length : lifetimeBoundsValue.length;
	}

	public function genericBoundIterator():Iterator<RustGenericBound> {
		return genericBounds.iterator();
	}

	public function lifetimeBoundIterator():Iterator<RustLifetime> {
		return lifetimeBoundsValue.iterator();
	}
}

/**
	An explicit, validated Rust where clause.

	Why / What / How
	- Declaration passes must distinguish no clause from a non-empty set of predicates without using
	  null or a pre-rendered suffix. Use `empty` when no clause exists and `of` for one or more typed
	  predicates. The class owns a defensive copy and exposes deterministic indexed/iterator access.
**/
class RustWhereClause {
	final predicates:Array<RustWherePredicate>;
	public var predicateCount(get, never):Int;

	private function new(predicates:Array<RustWherePredicate>) {
		this.predicates = predicates;
	}

	public static function empty():RustWhereClause {
		return new RustWhereClause([]);
	}

	public static function of(values:Array<RustWherePredicate>):RustWhereClause {
		if (values == null || values.length == 0)
			throw "Explicit Rust where clause requires at least one predicate";
		var copy = values.copy();
		for (predicate in copy) {
			if (predicate == null)
				throw "Rust where clause cannot contain a null predicate";
		}
		return new RustWhereClause(copy);
	}

	function get_predicateCount():Int {
		return predicates.length;
	}

	public function predicateAt(index:Int):RustWherePredicate {
		if (index < 0 || index >= predicates.length)
			throw 'Rust where predicate index out of bounds: $index';
		return predicates[index];
	}

	public function iterator():Iterator<RustWherePredicate> {
		return predicates.iterator();
	}
}

/**
	A structural associated function signature with an optional typed body.

	Why
	- Trait methods need receiver syntax (`&self`) that ordinary named function arguments cannot model.
	- A unit return written as `-> ()` is observably different output from an omitted return annotation,
	  so `returnType` is nullable instead of overloading `RUnit`.

	What
	- Owns visibility, async state, validated name, generics, optional receiver, named parameters,
	  optional explicit return type, function-level where clause, and optional typed body.

	How
	- `declaration` is the complete constructor. A null body is a trait signature; impl validation
	  requires bodies. Typed receivers admit named/aliased Self-rooted shapes (and borrows of them),
	  while definitely invalid primitives and compound non-receiver types fail at construction.
	  `fromFunction` adapts already-typed inherent methods without changing output.
**/
class RustAssociatedFunction {
	public final visibility:RustVisibility;
	public final name:RustIdentifier;
	public final isAsync:Bool;
	public final generics:RustGenericParameters;
	public final receiver:Null<RustSelfReceiver>;
	final parameters:Array<RustFunctionParameter>;
	public final returnType:Null<RustType>;
	public final whereClause:RustWhereClause;
	public final body:Null<RustBlock>;
	public var parameterCount(get, never):Int;

	private function new(visibility:RustVisibility, name:String, isAsync:Bool, generics:RustGenericParameters,
			receiver:Null<RustSelfReceiver>, parameters:Array<RustFunctionParameter>, returnType:Null<RustType>,
			whereClause:RustWhereClause, body:Null<RustBlock>) {
		if (visibility == null || generics == null || whereClause == null)
			throw "Rust associated function requires visibility, generics, and a where clause";
		this.visibility = visibility;
		this.name = RustIdentifier.named(name);
		this.isAsync = isAsync;
		this.generics = generics;
		this.receiver = validateReceiver(receiver);
		this.parameters = validateParameters(parameters);
		this.returnType = returnType;
		this.whereClause = whereClause;
		this.body = body;
	}

	public static function declaration(visibility:RustVisibility, name:String, isAsync:Bool, generics:RustGenericParameters,
			receiver:Null<RustSelfReceiver>, parameters:Array<RustFunctionParameter>, returnType:Null<RustType>,
			whereClause:RustWhereClause, body:Null<RustBlock>):RustAssociatedFunction {
		return new RustAssociatedFunction(visibility, name, isAsync, generics, receiver, parameters, returnType, whereClause, body);
	}

	public static function fromFunction(source:RustFunction):RustAssociatedFunction {
		if (source == null || source.body == null)
			throw "Cannot adapt a null or body-less Rust function";
		var visibility = source.vis != null ? source.vis : (source.isPub ? VPub : VPrivate);
		return declaration(visibility, source.name, source.isAsync == true, source.generics, null, [
			for (argument in source.args) RustFunctionParameter.named(argument.name, argument.ty)
		], source.ret == RUnit ? null : source.ret, RustWhereClause.empty(), source.body);
	}

	static function validateReceiver(receiver:Null<RustSelfReceiver>):Null<RustSelfReceiver> {
		if (receiver == null)
			return null;
		switch (receiver) {
			case ReceiverTyped(type, _):
				if (type == null)
					throw "Typed Rust self receiver requires a type";
				if (!couldResolveToSelfReceiver(type))
					throw "Typed Rust self receiver must be a named/aliased Self-rooted type or a borrow of one";
			case ReceiverBorrowed(_, _):
				// A null lifetime is the explicit, valid elided receiver-lifetime shape.
			case ReceiverValue(_):
		}
		return receiver;
	}

	static function couldResolveToSelfReceiver(type:RustType):Bool {
		return switch (type) {
			case RNamed(_): true;
			case RBorrow(inner, _, _):
				switch (inner) {
					case RNamed(_): true;
					case _: false;
				}
			case RUnit | RBool | RI32 | RF64 | RString | RTuple(_) | RSlice(_) | RArray(_, _) | RTraitObject(_): false;
		};
	}

	static function validateParameters(values:Array<RustFunctionParameter>):Array<RustFunctionParameter> {
		if (values == null)
			throw "Rust associated-function parameters cannot be null";
		var copy = values.copy();
		var seen:Map<String, Bool> = [];
		for (parameter in copy) {
			if (parameter == null)
				throw "Rust associated function cannot contain a null parameter";
			if (seen.exists(parameter.name.name))
				throw 'Duplicate Rust associated-function parameter `${parameter.name.name}`';
			seen.set(parameter.name.name, true);
		}
		return copy;
	}

	function get_parameterCount():Int {
		return parameters.length;
	}

	public function parameterAt(index:Int):RustFunctionParameter {
		if (index < 0 || index >= parameters.length)
			throw 'Rust associated-function parameter index out of bounds: $index';
		return parameters[index];
	}

	public function iterator():Iterator<RustFunctionParameter> {
		return parameters.iterator();
	}

	public function withBody(next:RustBlock):RustAssociatedFunction {
		if (next == null)
			throw "Rust associated-function body replacement cannot be null";
		return declaration(visibility, name.name, isAsync, generics, receiver, parameters, returnType, whereClause, next);
	}
}

/**
	A structural associated type signature, default, or trait-impl definition.

	Why / What / How
	- Associated types can carry their own generics, bounds, where predicates, and optional value; raw
	  text would hide every one of those paths from policy analysis.
	- `named` validates and defensively stores the declaration surface. A null `value` is a trait
	  declaration, while `RustTraitDeclaration` rejects values and `RustImpl` requires a value with no
	  declaration bounds. The printer places a definition's where clause after its value to avoid
	  Rust's deprecated pre-`=` GAT spelling.
**/
class RustAssociatedTypeDeclaration {
	public final name:RustIdentifier;
	public final generics:RustGenericParameters;
	final bounds:Array<RustGenericBound>;
	public final whereClause:RustWhereClause;
	public final value:Null<RustType>;
	public var boundCount(get, never):Int;

	private function new(name:String, generics:RustGenericParameters, bounds:Array<RustGenericBound>, whereClause:RustWhereClause,
			value:Null<RustType>) {
		if (generics == null || whereClause == null)
			throw "Rust associated type requires generics and a where clause";
		this.name = RustIdentifier.named(name);
		this.generics = generics;
		this.bounds = RustWherePredicate.validateGenericBounds(bounds, "Rust associated type", true);
		this.whereClause = whereClause;
		this.value = value;
	}

	public static function named(name:String, generics:RustGenericParameters, bounds:Array<RustGenericBound>, whereClause:RustWhereClause,
			value:Null<RustType>):RustAssociatedTypeDeclaration {
		return new RustAssociatedTypeDeclaration(name, generics, bounds, whereClause, value);
	}

	function get_boundCount():Int {
		return bounds.length;
	}

	public function iterator():Iterator<RustGenericBound> {
		return bounds.iterator();
	}
}

/**
	A structural associated constant signature, default, or trait-impl definition.

	Why / What / How
	- The constant type and optional initializer must remain traversable by no-runtime and expression
	  passes instead of being hidden in an impl-body string.
	- Visibility is structural because inherent impls may expose `pub` / `pub(crate)` constants, while
	  trait declarations and trait impls reject any visibility qualifier.
	- A null value is admitted for trait signatures; `RustImpl` requires an initializer. Construct with
	  `named` and use `withValue` when an expression mapper replaces that initializer.
**/
class RustAssociatedConstantDeclaration {
	public final visibility:RustVisibility;
	public final name:RustIdentifier;
	public final type:RustType;
	public final value:Null<RustExpr>;

	private function new(visibility:RustVisibility, name:String, type:RustType, value:Null<RustExpr>) {
		if (visibility == null || type == null)
			throw "Rust associated constant requires visibility and a type";
		this.visibility = visibility;
		this.name = RustIdentifier.named(name);
		this.type = type;
		this.value = value;
	}

	public static function named(visibility:RustVisibility, name:String, type:RustType, value:Null<RustExpr>):RustAssociatedConstantDeclaration {
		return new RustAssociatedConstantDeclaration(visibility, name, type, value);
	}

	public function withValue(next:RustExpr):RustAssociatedConstantDeclaration {
		if (next == null)
			throw "Rust associated-constant value replacement cannot be null";
		return named(visibility, name.name, type, next);
	}
}

/**
	Every associated item currently admitted inside a structural Rust trait or impl.

	Why / What / How
	- A closed enum makes every pass handle functions, types, constants, and the one remaining raw
	  metadata boundary explicitly.
	- `AssocRaw` is not general compiler authority: `RustTraitDeclaration` rejects it, and `RustImpl`
	  admits it only when the fragment is metadata-owned inside a trait impl.
**/
enum RustAssociatedItem {
	AssocFunction(method:RustAssociatedFunction);
	AssocType(declaration:RustAssociatedTypeDeclaration);
	AssocConst(declaration:RustAssociatedConstantDeclaration);
	AssocRaw(fragment:RustRawCode);
}

/**
	A validated structural Rust trait declaration.

	Why / What / How
	- Trait identity, generic bounds, supertraits, where predicates, and associated items all affect
	  dispatch and object safety. `named` stores each component structurally, rejects visibility on
	  trait-associated functions, rejects raw children, and defensively owns both bounds and items.
**/
class RustTraitDeclaration {
	public final visibility:RustVisibility;
	public final name:RustIdentifier;
	public final generics:RustGenericParameters;
	final supertraits:Array<RustGenericBound>;
	public final whereClause:RustWhereClause;
	final items:Array<RustAssociatedItem>;
	public var supertraitCount(get, never):Int;
	public var itemCount(get, never):Int;

	private function new(visibility:RustVisibility, name:String, generics:RustGenericParameters, supertraits:Array<RustGenericBound>,
			whereClause:RustWhereClause, items:Array<RustAssociatedItem>) {
		if (visibility == null || generics == null || whereClause == null)
			throw "Rust trait requires visibility, generics, and a where clause";
		this.visibility = visibility;
		this.name = RustIdentifier.named(name);
		this.generics = generics;
		this.supertraits = RustWherePredicate.validateGenericBounds(supertraits, "Rust trait supertrait list");
		this.whereClause = whereClause;
		this.items = validateItems(items);
	}

	public static function named(visibility:RustVisibility, name:String, generics:RustGenericParameters,
			supertraits:Array<RustGenericBound>, whereClause:RustWhereClause, items:Array<RustAssociatedItem>):RustTraitDeclaration {
		return new RustTraitDeclaration(visibility, name, generics, supertraits, whereClause, items);
	}

	static function validateItems(values:Array<RustAssociatedItem>):Array<RustAssociatedItem> {
		if (values == null)
			throw "Rust trait associated items cannot be null";
		var copy = values.copy();
		var typeNames:Map<String, Bool> = [];
		var valueNames:Map<String, Bool> = [];
		function claim(names:Map<String, Bool>, name:String, namespace:String):Void {
			if (names.exists(name))
				throw 'Duplicate Rust trait associated $namespace name `$name`';
			names.set(name, true);
		}
		for (item in copy) {
			if (item == null)
				throw "Rust trait cannot contain a null associated item";
			switch (item) {
				case AssocFunction(method):
					if (method == null)
						throw "Rust trait associated function cannot be null";
					if (method.visibility != VPrivate)
						throw "Rust trait associated functions cannot declare visibility";
					claim(valueNames, method.name.name, "value-namespace");
				case AssocType(declaration):
					if (declaration == null)
						throw "Rust trait associated type cannot be null";
					if (declaration.value != null)
						throw "Stable Rust trait associated types cannot declare default values";
					claim(typeNames, declaration.name.name, "type-namespace");
				case AssocConst(declaration):
					if (declaration == null)
						throw "Rust trait associated constant cannot be null";
					if (declaration.visibility != VPrivate)
						throw "Rust trait associated constants cannot declare visibility";
					claim(valueNames, declaration.name.name, "value-namespace");
				case AssocRaw(_):
					throw "Rust trait declarations cannot contain raw associated items";
			}
		}
		return copy;
	}

	function get_supertraitCount():Int {
		return supertraits.length;
	}

	function get_itemCount():Int {
		return items.length;
	}

	public function supertraitIterator():Iterator<RustGenericBound> {
		return supertraits.iterator();
	}

	public function itemAt(index:Int):RustAssociatedItem {
		if (index < 0 || index >= items.length)
			throw 'Rust trait associated-item index out of bounds: $index';
		return items[index];
	}

	public function iterator():Iterator<RustAssociatedItem> {
		return items.iterator();
	}

	public function withItems(next:Array<RustAssociatedItem>):RustTraitDeclaration {
		return named(visibility, name.name, generics, supertraits, whereClause, next);
	}
}

/**
	A validated inherent or trait Rust impl declaration.

	Why
	- A rendered impl header hides the implemented trait, target type, and where predicates from
	  ownership and policy analysis.
	- Inherent and trait impls admit different associated-item rules; one nullable string cannot enforce
	  them safely.

	What
	- Stores typed generics, an optional trait path, target type, where clause, and associated items.
	- Marker impls are represented by an empty item list. Metadata body text is permitted only as a
	  metadata-owned `AssocRaw` child under an otherwise structural trait impl.

	How
	- Use `inherent` to adapt existing typed functions, `inherentItems` for structural associated
	  constants/functions, and `traitImplementation` for a typed trait reference.
**/
class RustImpl {
	public final generics:RustGenericParameters;
	public final traitPath:Null<RustPath>;
	public final forType:RustType;
	public final whereClause:RustWhereClause;
	final items:Array<RustAssociatedItem>;
	public var itemCount(get, never):Int;
	public var isTraitImpl(get, never):Bool;

	private function new(generics:RustGenericParameters, traitPath:Null<RustPath>, forType:RustType, whereClause:RustWhereClause,
			items:Array<RustAssociatedItem>) {
		if (generics == null || forType == null || whereClause == null)
			throw "Rust impl requires generics, a target type, and a where clause";
		this.generics = generics;
		this.traitPath = traitPath;
		this.forType = forType;
		this.whereClause = whereClause;
		this.items = validateItems(traitPath != null, items);
	}

	public static function inherent(generics:RustGenericParameters, forType:RustType, functions:Array<RustFunction>):RustImpl {
		if (functions == null)
			throw "Rust inherent impl functions cannot be null";
		return inherentItems(generics, forType, RustWhereClause.empty(), [
			for (source in functions) AssocFunction(RustAssociatedFunction.fromFunction(source))
		]);
	}

	public static function inherentItems(generics:RustGenericParameters, forType:RustType, whereClause:RustWhereClause,
			items:Array<RustAssociatedItem>):RustImpl {
		return new RustImpl(generics, null, forType, whereClause, items);
	}

	public static function traitImplementation(generics:RustGenericParameters, traitPath:RustPath, forType:RustType,
			whereClause:RustWhereClause, items:Array<RustAssociatedItem>):RustImpl {
		if (traitPath == null)
			throw "Rust trait impl requires a trait path";
		return new RustImpl(generics, traitPath, forType, whereClause, items);
	}

	static function validateItems(traitImpl:Bool, values:Array<RustAssociatedItem>):Array<RustAssociatedItem> {
		if (values == null)
			throw "Rust impl associated items cannot be null";
		var copy = values.copy();
		var typeNames:Map<String, Bool> = [];
		var valueNames:Map<String, Bool> = [];
		function claim(names:Map<String, Bool>, name:String, namespace:String):Void {
			if (names.exists(name))
				throw 'Duplicate Rust impl associated $namespace name `$name`';
			names.set(name, true);
		}
		for (item in copy) {
			if (item == null)
				throw "Rust impl cannot contain a null associated item";
			switch (item) {
				case AssocFunction(method):
					if (method == null || method.body == null)
						throw "Rust impl associated functions require typed bodies";
					if (traitImpl && method.visibility != VPrivate)
						throw "Rust trait impl associated functions cannot declare visibility";
					claim(valueNames, method.name.name, "value-namespace");
				case AssocType(declaration):
					if (!traitImpl)
						throw "Rust inherent impls cannot contain associated type declarations";
					if (declaration == null || declaration.value == null)
						throw "Rust trait impl associated types require values";
					if (declaration.boundCount != 0)
						throw "Rust trait impl associated type definitions cannot declare bounds";
					claim(typeNames, declaration.name.name, "type-namespace");
				case AssocConst(declaration):
					if (declaration == null || declaration.value == null)
						throw "Rust impl associated constants require values";
					if (traitImpl && declaration.visibility != VPrivate)
						throw "Rust trait impl associated constants cannot declare visibility";
					claim(valueNames, declaration.name.name, "value-namespace");
				case AssocRaw(fragment):
					if (!traitImpl)
						throw "Raw associated bodies are admitted only for trait impl metadata";
					if (fragment == null || fragment.authorityId() != "metadata-owned")
						throw "Raw trait impl bodies must retain metadata authority";
			}
		}
		return copy;
	}

	function get_itemCount():Int {
		return items.length;
	}

	function get_isTraitImpl():Bool {
		return traitPath != null;
	}

	public function itemAt(index:Int):RustAssociatedItem {
		if (index < 0 || index >= items.length)
			throw 'Rust impl associated-item index out of bounds: $index';
		return items[index];
	}

	public function iterator():Iterator<RustAssociatedItem> {
		return items.iterator();
	}

	public function withItems(next:Array<RustAssociatedItem>):RustImpl {
		return traitPath == null ? inherentItems(generics, forType, whereClause, next) : traitImplementation(generics, traitPath, forType, whereClause, next);
	}
}

typedef RustFunction = {
	var name:String;
	var isPub:Bool;
	@:optional var vis:RustVisibility;
	@:optional var isAsync:Bool;
	var generics:RustGenericParameters;
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
	RNamed(path:RustPath);
	RBorrow(inner:RustType, mutable:Bool, lifetime:Null<RustLifetime>);
	RTuple(elements:Array<RustType>);
	RSlice(element:RustType);
	RArray(element:RustType, length:RustConstArgument);
	RTraitObject(object:RustTraitObject);
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
	PPath(path:RustPath);
	PLitInt(v:Int);
	/**
		Carries a stable `u32` pattern without target-literal text.

		Why
		- Compiler-generated type IDs may set the high bit and therefore cannot be represented as a
		  positive Haxe `Int` or a Rust signed pattern.

		What
		- Stores the exact 32 bits in Haxe's signed `Int` representation.

		How
		- The printer renders canonical eight-digit hexadecimal plus the `u32` suffix.
	**/
	PLitUInt32(bits:Int);
	PLitBool(v:Bool);
	PLitString(v:String);
	/**
		A structural tuple pattern.

		Why
		- Closure destructuring such as `|(key, value)|` must expose lexical bindings to ownership passes.

		What
		- Stores child patterns in source order without rendered parentheses or commas.

		How
		- The printer owns tuple punctuation, including the required comma for a single-element tuple.
	**/
	PTuple(fields:Array<RustPattern>);
	PTupleStruct(path:RustPath, fields:Array<RustPattern>);
	/**
		A Rust or-pattern with at least two alternatives when admitted by a validated AST boundary.

		Why
		- Or-pattern precedence is lower than aliases and nested pattern positions, so the printer must
		  own the required parentheses instead of callers embedding them in strings.

		What
		- Stores alternatives without `|` tokens or parentheses.

		How
		- Compiler lowering constructs this only for two or more alternatives. Validating wrappers such
		  as `RustClosureParameter` reject shorter lists; the printer also fails closed for direct AST use.
	**/
	POr(patterns:Array<RustPattern>);
}

/**
	One structural Rust closure parameter.

	Why
	- Rendered parameter strings hid typed bindings and tuple destructuring from shadowing, ownership,
	  and no-runtime analysis.
	- Closure parameters need patterns, while function declarations intentionally retain their simpler
	  named-argument contract.

	What
	- Couples one `RustPattern` with an optional structural `RustType` annotation.
	- Binding factories validate that a bare name contains no punctuation, type syntax, or Rust keyword.

	How
	- Use `binding` / `typedBinding` for the common named forms.
	- Use `pattern` / `typedPattern` for tuple, alias, or other already-structural patterns.
	- The printer owns `:`, tuple punctuation, and closure delimiters.
	- Validation covers the supplied tree at construction time. `RustPattern` remains shared mutable AST;
	  callers must not mutate compound-pattern arrays after wrapping them.
**/
class RustClosureParameter {
	public final patternValue:RustPattern;
	public final ty:Null<RustType>;

	private function new(pattern:RustPattern, ty:Null<RustType>) {
		if (pattern == null)
			throw "Rust closure parameter pattern cannot be null";
		validatePattern(pattern);
		this.patternValue = pattern;
		this.ty = ty;
	}

	public static function binding(name:String):RustClosureParameter {
		return pattern(PBind(validBindingName(name)));
	}

	public static function typedBinding(name:String, ty:RustType):RustClosureParameter {
		return typedPattern(PBind(validBindingName(name)), ty);
	}

	public static function pattern(value:RustPattern):RustClosureParameter {
		return new RustClosureParameter(value, null);
	}

	public static function typedPattern(value:RustPattern, ty:RustType):RustClosureParameter {
		if (ty == null)
			throw "Typed Rust closure parameter requires a type";
		return new RustClosureParameter(value, ty);
	}

	static function validBindingName(name:String):String {
		return RustIdentifier.named(name).name;
	}

	static function validatePattern(value:RustPattern):Void {
		switch (value) {
			case PBind(name):
				validBindingName(name);
			case PAlias(name, inner):
				validBindingName(name);
				if (inner == null)
					throw "Rust closure alias pattern cannot contain a null pattern";
				validatePattern(inner);
			case PPath(path):
				if (path == null)
					throw "Rust closure path pattern cannot be null";
			case PTupleStruct(path, fields):
				if (path == null)
					throw "Rust closure tuple-struct pattern path cannot be null";
				validatePatternFields(fields);
			case PTuple(fields):
				validatePatternFields(fields);
			case POr(fields):
				if (fields == null || fields.length < 2)
					throw "Rust closure or-pattern requires at least two alternatives";
				validatePatternFields(fields);
			case PWildcard | PLitInt(_) | PLitUInt32(_) | PLitBool(_) | PLitString(_):
		}
	}

	static function validatePatternFields(fields:Array<RustPattern>):Void {
		if (fields == null)
			throw "Rust closure compound pattern fields cannot be null";
		for (field in fields) {
			if (field == null)
				throw "Rust closure compound pattern cannot contain a null field";
			validatePattern(field);
		}
	}
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
	/**
		The structural Rust value receiver keyword used inside associated method bodies.

		Why / What / How
		- `self` is a Rust keyword expression, not a relative identifier path. Keeping it distinct prevents
		  callers from weakening `RustIdentifier` validation just to print receiver reads.
		- Expression passes treat this node as a leaf and the printer emits the keyword exactly once.
	**/
	ESelf;
	/**
		The Rust unit value `()`.

		Why / What / How
		- An empty block also evaluates to unit, but printing `{ }` as a call argument is noisier and
		  falsely suggests a scoped computation. `ELitUnit` preserves the exact value shape a Rust
		  developer would write and lets expression passes classify it as a pure literal.
	**/
	ELitUnit;
	ELitInt(v:Int);
	/**
		Carries a stable `u32` expression literal without disguising it as a path or raw fragment.

		Why
		- Compiler-generated type IDs need all 32 bits, including values above signed `i32::MAX`.

		What
		- Stores the exact bit pattern in Haxe's signed `Int` representation.

		How
		- The printer owns hexadecimal/suffix syntax; passes may safely recognize the node as a copyable
		  literal.
	**/
	ELitUInt32(bits:Int);
	ELitFloat(v:Float);
	ELitBool(v:Bool);
	ELitString(v:String);
	EPath(path:RustPath);
	ECall(func:RustExpr, args:Array<RustExpr>);
	EMacroCall(name:String, args:Array<RustExpr>);
	EClosure(args:Array<RustClosureParameter>, body:RustBlock, isMove:Bool);
	EBinary(op:String, left:RustExpr, right:RustExpr);
	EUnary(op:String, expr:RustExpr);
	ERange(start:RustExpr, end:RustExpr);
	ECast(expr:RustExpr, ty:RustType);
	EIndex(recv:RustExpr, index:RustExpr);
	EStructLit(path:RustPath, fields:Array<RustStructLitField>);
	EBlock(b:RustBlock);
	EIf(cond:RustExpr, thenExpr:RustExpr, elseExpr:Null<RustExpr>);
	EMatch(scrutinee:RustExpr, arms:Array<RustMatchArm>);
	EAssign(lhs:RustExpr, rhs:RustExpr);
	EField(recv:RustExpr, field:RustMember);
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
