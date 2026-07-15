package reflaxe.rust.ast;

import reflaxe.rust.ast.RustAST.RustConstArgument;
import reflaxe.rust.ast.RustAST.RustGenericParameters;
import reflaxe.rust.ast.RustAST.RustIdentifier;
import reflaxe.rust.ast.RustAST.RustPath;
import reflaxe.rust.ast.RustAST.RustPattern;
import reflaxe.rust.ast.RustAST.RustType;

/**
	Shared semantic queries and traversal for structural Rust paths.

	Why
	- Ownership, mutation, clone-elision, and runtime-policy passes must agree on what is a local,
	  which exact target function a path denotes, and whether nested syntax references `hxrt`.
	- Reimplementing those rules in each pass invites delimiter parsing, prefix collisions, and missed
	  paths hidden inside qualified roots or generic type/const arguments.

	What
	- Provides exact local identity, plain relative target matching, and leading namespace ownership.
	- Walks every path nested through qualified roots, types, const arguments, trait bounds, function-
	  trait inputs/outputs, and declaration generic defaults.

	How
	- Callers supply compiler-owned identifier names only to the exact predicate functions; path
	  punctuation and generic syntax remain owned by `RustPath` and the printer.
	- Visitors receive validated `RustPath` nodes in deterministic pre-order and never rendered text.
**/
class RustPathAnalysis {
	/**
		Returns the local-shaped identifier represented by a path.

		Why
		- Every ownership-oriented pass must reject qualified, rooted, and generic paths consistently.

		What
		- Admits one argument-free relative segment and returns `null` for every target-shaped path.

		How
		- Delegates the closed shape check to `RustPath`; callers still decide whether the returned name
		  belongs to the current lexical binding table.
	**/
	public static function localIdentifierName(path:RustPath):Null<String> {
		return path == null ? null : path.plainRelativeIdentifierName();
	}

	/**
		Compares a path with one compiler-owned plain relative target path.

		Why
		- Clone and ownership rules must not infer target identity from printed `::` delimiters or accept
		  prefix/descendant collisions.

		What
		- Requires a relative root, the exact segment count, exact identifier names, and no generic or
		  parenthesized arguments on any segment.

		How
		- `expectedNames` contains bare target identifier tokens, not a rendered path. Each token is
		  validated before comparison so punctuation cannot cross this boundary.
	**/
	public static function matchesPlainRelative(path:RustPath, expectedNames:Array<String>):Bool {
		if (path == null
			|| expectedNames == null
			|| expectedNames.length == 0
			|| !path.isRelative()
			|| path.segmentCount != expectedNames.length)
			return false;
		for (index in 0...expectedNames.length) {
			var expected = RustIdentifier.named(expectedNames[index]);
			var segment = path.segmentAt(index);
			if (segment.identifier.name != expected.name || segment.argumentStyle != PathArgumentsNone)
				return false;
		}
		return true;
	}

	/**
		Reports whether a path is owned by one exact leading namespace.

		Why
		- Runtime policy must recognize `hxrt` without also accepting `hxrtual`, a later `hxrt` segment,
		  or a generic value path whose first identifier merely has the same spelling.

		What
		- Checks the first segment's complete identifier and requires that segment to be argument-free.
		- Root kind is intentionally preserved but does not hide the namespace: `hxrt::...` and
		  `crate::hxrt::...` both expose the same leading structural namespace segment.

		How
		- The namespace is a single validated compiler-owned identifier token. Nested paths are not
		  searched here; use the visitor functions to inspect a complete path tree.
	**/
	public static function belongsToNamespace(path:RustPath, namespace:String):Bool {
		if (path == null || path.segmentCount == 0)
			return false;
		var expected = RustIdentifier.named(namespace);
		var first = path.segmentAt(0);
		return first.argumentStyle == PathArgumentsNone && first.identifier.name == expected.name;
	}

	/**
		Visits one path plus every path nested inside its structural syntax.

		Why
		- Qualified self/trait roots and type, const, lifetime, and function-trait arguments may hide
		  analysis-critical namespaces several levels below the printed outer path.

		What
		- Emits the supplied path first, then qualified roots, then each segment's arguments in source
		  order. Lifetimes are already typed and contain no paths, so they require no callback.

		How
		- The callback receives only `RustPath`; recursive types and const paths are expanded internally.
	**/
	public static function visitPathTree(path:RustPath, visitor:RustPath->Void):Void {
		validateVisit(path, visitor, "path");
		visitPathTreeInternal(path, visitor);
	}

	/**
		Visits every structural path reachable from a Rust type.

		Why
		- Runtime and ownership policy applies equally to nominal types, borrows, tuples, arrays, and
		  trait-object bounds, including their nested generics and const lengths.

		What
		- Covers every current closed `RustType` variant without converting it to printer text.

		How
		- Traversal delegates nominal and trait-bound paths to `visitPathTree` semantics and ignores only
		  primitive/unit types, which contain no path payload.
	**/
	public static function visitTypeTree(type:RustType, visitor:RustPath->Void):Void {
		if (type == null)
			throw "Cannot visit a null Rust type";
		if (visitor == null)
			throw "Rust path visitor cannot be null";
		visitTypeTreeInternal(type, visitor);
	}

	/**
		Visits every structural path reachable from a Rust pattern.

		Why
		- Runtime-policy paths can occur below tuple-struct, alternation, and alias patterns; skipping an
		  alias wrapper would make a fail-closed policy depend on incidental pattern shape.

		What
		- Covers every current closed `RustPattern` variant and recursively expands every path's type and
		  const arguments through the same traversal used for expressions and declarations.

		How
		- The callback receives tuple-struct and path-pattern nodes in source order. Binding and literal
		  patterns contain no paths and therefore produce no callback.
	**/
	public static function visitPatternTree(pattern:RustPattern, visitor:RustPath->Void):Void {
		if (pattern == null)
			throw "Cannot visit a null Rust pattern";
		if (visitor == null)
			throw "Rust path visitor cannot be null";
		visitPatternTreeInternal(pattern, visitor);
	}

	/**
		Visits every path reachable from declaration generic parameters.

		Why
		- Trait bounds, default types, const parameter types, and const defaults participate in no-hxrt
		  and ownership contracts even when no expression mentions them.

		What
		- Traverses type-parameter trait bounds/defaults and const-parameter types/defaults in declaration
		  order. Lifetime-only bounds contain no paths.

		How
		- Pass the declaration's validated `RustGenericParameters`; the callback receives the same
		  deterministic path stream used for expression and type analysis.
	**/
	public static function visitGenericParameters(parameters:RustGenericParameters, visitor:RustPath->Void):Void {
		if (parameters == null)
			throw "Cannot visit null Rust generic parameters";
		if (visitor == null)
			throw "Rust path visitor cannot be null";
		for (parameter in parameters) {
			switch (parameter) {
				case GenericLifetimeParam(_, _):
				case GenericTypeParam(_, bounds, defaultType):
					for (bound in bounds) {
						switch (bound) {
							case GenericTraitBound(path, _): visitPathTreeInternal(path, visitor);
							case GenericLifetimeBound(_):
						}
					}
					if (defaultType != null)
						visitTypeTreeInternal(defaultType, visitor);
				case GenericConstParam(_, type, defaultValue):
					visitTypeTreeInternal(type, visitor);
					if (defaultValue != null)
						visitConstArgumentInternal(defaultValue, visitor);
			}
		}
	}

	static function validateVisit(path:RustPath, visitor:RustPath->Void, label:String):Void {
		if (path == null)
			throw 'Cannot visit a null Rust $label';
		if (visitor == null)
			throw "Rust path visitor cannot be null";
	}

	static function visitPathTreeInternal(path:RustPath, visitor:RustPath->Void):Void {
		visitor(path);
		switch (path.root) {
			case PathQualified(selfType, traitPath):
				visitTypeTreeInternal(selfType, visitor);
				if (traitPath != null)
					visitPathTreeInternal(traitPath, visitor);
			case _:
		}
		for (segment in path) {
			switch (segment.argumentStyle) {
				case PathArgumentsAngle:
					for (index in 0...segment.genericArgumentCount) {
						switch (segment.genericArgumentAt(index)) {
							case GenericType(type): visitTypeTreeInternal(type, visitor);
							case GenericConst(argument): visitConstArgumentInternal(argument, visitor);
							case GenericLifetime(_):
						}
					}
				case PathArgumentsParenthesized:
					for (index in 0...segment.inputTypeCount)
						visitTypeTreeInternal(segment.inputTypeAt(index), visitor);
					if (segment.outputType != null)
						visitTypeTreeInternal(segment.outputType, visitor);
				case PathArgumentsNone:
			}
		}
	}

	static function visitTypeTreeInternal(type:RustType, visitor:RustPath->Void):Void {
		switch (type) {
			case RNamed(path):
				visitPathTreeInternal(path, visitor);
			case RBorrow(inner, _, _):
				visitTypeTreeInternal(inner, visitor);
			case RTuple(elements):
				for (element in elements)
					visitTypeTreeInternal(element, visitor);
			case RSlice(element):
				visitTypeTreeInternal(element, visitor);
			case RArray(element, length):
				visitTypeTreeInternal(element, visitor);
				visitConstArgumentInternal(length, visitor);
			case RTraitObject(object):
				for (bound in object) {
					switch (bound) {
						case GenericTraitBound(path, _): visitPathTreeInternal(path, visitor);
						case GenericLifetimeBound(_):
					}
				}
			case RUnit | RBool | RI32 | RF64 | RString:
		}
	}

	static function visitPatternTreeInternal(pattern:RustPattern, visitor:RustPath->Void):Void {
		switch (pattern) {
			case PAlias(_, inner):
				visitPatternTreeInternal(inner, visitor);
			case PPath(path):
				visitPathTreeInternal(path, visitor);
			case PTupleStruct(path, fields):
				visitPathTreeInternal(path, visitor);
				for (field in fields)
					visitPatternTreeInternal(field, visitor);
			case POr(patterns):
				for (entry in patterns)
					visitPatternTreeInternal(entry, visitor);
			case PWildcard | PBind(_) | PLitInt(_) | PLitUInt32(_) | PLitBool(_) | PLitString(_):
		}
	}

	static function visitConstArgumentInternal(argument:RustConstArgument, visitor:RustPath->Void):Void {
		switch (argument.kind) {
			case ConstPath:
				if (argument.pathValue != null)
					visitPathTreeInternal(argument.pathValue, visitor);
			case ConstInteger | ConstBoolean:
		}
	}
}
