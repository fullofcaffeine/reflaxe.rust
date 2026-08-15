package reflaxe.rust;

#if macro
import haxe.ds.ObjectMap;
import haxe.io.Bytes;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.TypedExprTools;
import reflaxe.rust.RustDiagnostic.RustDiagnosticId;
import reflaxe.rust.SupportCrateRequestPlan.SupportCrateDeclarationOwner;
import reflaxe.rust.SupportCrateRequestPlan.SupportCrateRegistryDependency;
import reflaxe.rust.SupportCrateRequestPlan.SupportCrateRequest;
import reflaxe.rust.SupportCrateRequestPlan.SupportCrateUnsafePolicy;
import reflaxe.rust.ast.RustAST.RustPathRoot;
import reflaxe.rust.ast.RustAST.RustPathSegmentArgumentStyle;
import reflaxe.rust.metadata.RustMetadataSyntax;
import reflaxe.rust.naming.RustNaming;

/** Detached failure retained until compile-start can report it safely. */
final class SupportCratePlanningFailure {
	public final id:RustDiagnosticId;
	public final detail:String;
	public final pos:Position;

	public function new(id:RustDiagnosticId, detail:String, pos:Position) {
		this.id = id;
		this.detail = detail;
		this.pos = pos;
	}
}

/** Request-local identity guards for the typed placement graph. */
private final class SupportCratePlacementState {
	public final anonymousTypes:ObjectMap<AnonType, Bool> = new ObjectMap();
	public final fields:ObjectMap<ClassField, Bool> = new ObjectMap();

	public function new() {}
}

/**
	Builds the pure Stage 2A support-crate request plan from typed declarations.

	Why
	- `@:rustSupportCrate` is a public security and packaging boundary. Unknown
	  metadata or partial parsing must not silently widen that boundary.
	- A warm compiler server must not merge declarations across requests.

	What
	- Accepts the exact five-field object grammar only on extern classes.
	- Normalizes logical paths, targets, features, and dependencies, then merges
	  repeated crate declarations only when every normalized fact is equal.
	- Rejects every other typed placement, including anonymous typedef fields,
	  abstract implementation fields, and preserved expression metadata.

	How
	- Runs while Haxe still exposes complete typed metadata.
	- Returns only detached request data or a detached diagnostic.
	- Parses ordered object fields directly, so duplicate fields cannot disappear
	  through a map conversion.
	- Performs no filesystem operation and retains no process-static state.
**/
class SupportCrateRequestPlanner {
	static inline final MAX_SOURCE_ROOT_SEGMENTS = 32;
	static inline final MAX_SOURCE_ROOT_SEGMENT_BYTES = 255;
	public static function build(moduleTypes:Array<ModuleType>, rustTarget:Null<String>):SupportCrateRequestPlan {
		var requests:Array<SupportCrateRequest> = [];
		var placement = new SupportCratePlacementState();
		for (moduleType in moduleTypes) {
			switch (moduleType) {
				case TClassDecl(classRef):
					var classType = classRef.get();
					collectClassMetadata(classType, rustTarget, requests);
					rejectTypeParameterPlacements(classType.params, placement);
					switch (classType.kind) {
						case KGenericInstance(_, parameters):
							for (parameter in parameters)
								rejectTypeFieldPlacement(parameter, placement);
						case _:
					}
					if (classType.superClass != null) {
						for (parameter in classType.superClass.params)
							rejectTypeFieldPlacement(parameter, placement);
					}
					for (implemented in classType.interfaces) {
						for (parameter in implemented.params)
							rejectTypeFieldPlacement(parameter, placement);
					}
					for (field in classType.fields.get())
						rejectFieldPlacement(field, placement);
					for (field in classType.statics.get())
						rejectFieldPlacement(field, placement);
					if (classType.constructor != null)
						rejectFieldPlacement(classType.constructor.get(), placement);
					for (fieldRef in classType.overrides)
						rejectFieldPlacement(fieldRef.get(), placement);
					if (classType.init != null)
						rejectExpressionPlacement(classType.init, placement);
				case TEnumDecl(enumRef):
					var enumType = enumRef.get();
					rejectMetadataPlacement(enumType.meta, "an enum");
					rejectTypeParameterPlacements(enumType.params, placement);
					for (constructorName in enumType.names) {
						var constructor = enumType.constructs.get(constructorName);
						rejectMetadataPlacement(constructor.meta, "an enum constructor");
						rejectTypeParameterPlacements(constructor.params, placement);
						rejectTypeFieldPlacement(constructor.type, placement);
					}
				case TTypeDecl(typeRef):
					var typeDefinition = typeRef.get();
					rejectMetadataPlacement(typeDefinition.meta, "a typedef");
					rejectTypeParameterPlacements(typeDefinition.params, placement);
					rejectTypeFieldPlacement(typeDefinition.type, placement);
				case TAbstract(abstractRef):
					var abstractType = abstractRef.get();
					rejectMetadataPlacement(abstractType.meta, "an abstract");
					rejectTypeParameterPlacements(abstractType.params, placement);
					rejectTypeFieldPlacement(abstractType.type, placement);
					if (abstractType.impl != null) {
						var implementation = abstractType.impl.get();
						for (field in implementation.fields.get())
							rejectFieldPlacement(field, placement);
						for (field in implementation.statics.get())
							rejectFieldPlacement(field, placement);
						if (implementation.constructor != null)
							rejectFieldPlacement(implementation.constructor.get(), placement);
					}
					for (operation in abstractType.binops)
						rejectFieldPlacement(operation.field, placement);
					for (operation in abstractType.unops)
						rejectFieldPlacement(operation.field, placement);
					for (conversion in abstractType.from) {
						rejectTypeFieldPlacement(conversion.t, placement);
						if (conversion.field != null)
							rejectFieldPlacement(conversion.field, placement);
					}
					for (conversion in abstractType.to) {
						rejectTypeFieldPlacement(conversion.t, placement);
						if (conversion.field != null)
							rejectFieldPlacement(conversion.field, placement);
					}
					for (field in abstractType.array)
						rejectFieldPlacement(field, placement);
					if (abstractType.resolve != null)
						rejectFieldPlacement(abstractType.resolve, placement);
					if (abstractType.resolveWrite != null)
						rejectFieldPlacement(abstractType.resolveWrite, placement);
			}
		}
		requests.sort(compareRequests);
		return new SupportCrateRequestPlan(requests);
	}

	public static function merge(plans:Array<SupportCrateRequestPlan>):SupportCrateRequestPlan {
		var requests:Array<SupportCrateRequest> = [];
		for (plan in plans) {
			for (request in plan.requests()) {
				var owners = request.owners();
				if (owners.length == 0)
					throw "internal support-crate request without a declaration owner";
				mergeRequest(requests, request, owners[0].pos);
			}
		}
		requests.sort(compareRequests);
		return new SupportCrateRequestPlan(requests);
	}

	static function collectClassMetadata(classType:ClassType, rustTarget:Null<String>, requests:Array<SupportCrateRequest>):Void {
		for (entry in classType.meta.get()) {
			if (!isSupportMetadata(entry.name))
				continue;
			if (!classType.isExtern || classType.isInterface)
				fail(RustDiagnosticId.MetadataPlacement, "`@:rustSupportCrate` can appear only on an extern class.", entry.pos);
			var request = parseDeclaration(classType, entry, rustTarget);
			mergeRequest(requests, request, entry.pos);
		}
	}

	static function parseDeclaration(classType:ClassType, entry:MetadataEntry, rustTarget:Null<String>):SupportCrateRequest {
		if (entry.params == null || entry.params.length != 1)
			return fail(RustDiagnosticId.MetadataArity, "`@:rustSupportCrate` requires exactly one object argument.", entry.pos);
		var fields = switch (entry.params[0].expr) {
			case EObjectDecl(values): values;
			case _: return fail(RustDiagnosticId.MetadataValue, "`@:rustSupportCrate` requires exactly one object argument.", entry.pos);
		};

		var name:Null<String> = null;
		var sourceRoot:Null<String> = null;
		var unsafePolicy:Null<String> = null;
		var targets:Null<Array<String>> = null;
		var dependencies:Null<Array<SupportCrateRegistryDependency>> = null;
		var seen:Array<String> = [];
		for (field in fields) {
			if (seen.indexOf(field.field) >= 0)
				return fail(RustDiagnosticId.MetadataValue, "`@:rustSupportCrate` has duplicate field `" + field.field + "`.", field.expr.pos);
			seen.push(field.field);
			switch (field.field) {
				case "name": name = requireString(field.expr, "name");
				case "sourceRoot": sourceRoot = requireString(field.expr, "sourceRoot");
				case "unsafePolicy": unsafePolicy = requireString(field.expr, "unsafePolicy");
				case "targets": targets = requireStringArray(field.expr, "targets");
				case "dependencies": dependencies = parseDependencies(field.expr);
				case _: return fail(RustDiagnosticId.MetadataValue, "`@:rustSupportCrate` has unknown field `" + field.field + "`.", field.expr.pos);
			}
		}

		for (required in ["name", "sourceRoot", "unsafePolicy", "targets", "dependencies"]) {
			if (seen.indexOf(required) < 0)
				return fail(RustDiagnosticId.MetadataValue, "`@:rustSupportCrate` is missing required field `" + required + "`.", entry.pos);
		}
		if (!isLowerRustIdentifier(name))
			return fail(RustDiagnosticId.MetadataValue, "`@:rustSupportCrate.name` must be one lowercase Rust identifier.", entry.pos);
		var sourceRootSegments = normalizeSourceRoot(sourceRoot, entry.pos);
		var parsedUnsafePolicy = switch (unsafePolicy) {
			case "forbid": SupportCrateUnsafePolicy.Forbid;
			case "audited": SupportCrateUnsafePolicy.Audited;
			case _: return fail(RustDiagnosticId.MetadataValue, "`@:rustSupportCrate.unsafePolicy` must be `forbid` or `audited`.", entry.pos);
		};
		var normalizedTargets = normalizeTargets(targets, rustTarget, entry.pos);
		for (dependency in dependencies) {
			if (dependency.name == name)
				return fail(RustDiagnosticId.MetadataValue, "A support crate cannot depend on itself.", entry.pos);
		}
		dependencies.sort(compareDependencies);
		validateNativePrefix(classType, name, entry.pos);

		var declaration = classType.pack.concat([classType.name]).join(".");
		return new SupportCrateRequest(name, sourceRootSegments, parsedUnsafePolicy, normalizedTargets, dependencies,
			[new SupportCrateDeclarationOwner(declaration, entry.pos)]);
	}

	static function mergeRequest(requests:Array<SupportCrateRequest>, incoming:SupportCrateRequest, pos:Position):Void {
		for (index in 0...requests.length) {
			var existing = requests[index];
			if (existing.name != incoming.name)
				continue;
			if (!existing.hasSameDeclaration(incoming))
				fail(RustDiagnosticId.MetadataValue, "Conflicting `@:rustSupportCrate` declaration for crate `" + incoming.name + "`.", pos);
			var merged = existing;
			for (owner in incoming.owners())
				merged = merged.withOwner(owner);
			requests[index] = merged;
			return;
		}
		requests.push(incoming);
	}

	static function parseDependencies(expression:Expr):Array<SupportCrateRegistryDependency> {
		var values = switch (expression.expr) {
			case EArrayDecl(items): items;
			case _: return fail(RustDiagnosticId.MetadataValue, "`@:rustSupportCrate.dependencies` must be an array.", expression.pos);
		};
		var dependencies:Array<SupportCrateRegistryDependency> = [];
		for (value in values) {
			var fields = switch (value.expr) {
				case EObjectDecl(entries): entries;
				case _: return fail(RustDiagnosticId.MetadataValue, "Each support-crate dependency must use the documented object form.", value.pos);
			};
			var name:Null<String> = null;
			var version:Null<String> = null;
			var defaultFeatures:Null<Bool> = null;
			var features:Null<Array<String>> = null;
			var seen:Array<String> = [];
			for (field in fields) {
				if (seen.indexOf(field.field) >= 0)
					return fail(RustDiagnosticId.MetadataValue, "Support-crate dependency has duplicate field `" + field.field + "`.", field.expr.pos);
				seen.push(field.field);
				switch (field.field) {
					case "name": name = requireString(field.expr, "dependencies[].name");
					case "version": version = requireString(field.expr, "dependencies[].version");
					case "defaultFeatures": defaultFeatures = requireBool(field.expr, "dependencies[].defaultFeatures");
					case "features": features = requireStringArray(field.expr, "dependencies[].features");
					case _: return fail(RustDiagnosticId.MetadataValue, "Support-crate dependency has unknown field `" + field.field + "`.", field.expr.pos);
				}
			}
			for (required in ["name", "version", "defaultFeatures", "features"]) {
				if (seen.indexOf(required) < 0)
					return fail(RustDiagnosticId.MetadataValue, "Support-crate dependency is missing required field `" + required + "`.", value.pos);
			}
			if (!isCargoPackageName(name))
				return fail(RustDiagnosticId.MetadataValue, "Support-crate dependency name must use lowercase Cargo package characters.", value.pos);
			if (!isExactVersion(version))
				return fail(RustDiagnosticId.MetadataValue, "Support-crate dependencies require an exact registry version such as `=1.2.3`.", value.pos);
			features = uniqueSorted(features, "dependency feature", value.pos, isCargoFeatureName);
			for (existing in dependencies) {
				if (existing.name == name)
					return fail(RustDiagnosticId.MetadataValue, "Duplicate support-crate dependency `" + name + "`.", value.pos);
			}
			dependencies.push(new SupportCrateRegistryDependency(name, version, defaultFeatures, features));
		}
		return dependencies;
	}

	static function normalizeSourceRoot(value:String, pos:Position):Array<String> {
		if (value == null || value.length == 0 || value.charAt(0) == "/" || value.indexOf("\\") >= 0 || value.indexOf(":") >= 0)
			return fail(RustDiagnosticId.MetadataValue, "`@:rustSupportCrate.sourceRoot` must be a relative slash-separated logical path.", pos);
		var segments = value.split("/");
		if (segments.length > MAX_SOURCE_ROOT_SEGMENTS)
			return fail(RustDiagnosticId.MetadataValue,
				"`@:rustSupportCrate.sourceRoot` has more than 32 path segments.", pos);
		for (segment in segments) {
			if (segment.length == 0 || segment == "." || segment == ".." || segment.indexOf("\x00") >= 0)
				return fail(RustDiagnosticId.MetadataValue, "`@:rustSupportCrate.sourceRoot` contains an empty, current-directory, or parent-directory segment.", pos);
			if (Bytes.ofString(segment).length > MAX_SOURCE_ROOT_SEGMENT_BYTES)
				return fail(RustDiagnosticId.MetadataValue,
					"`@:rustSupportCrate.sourceRoot` contains a path segment above 255 UTF-8 bytes.", pos);
		}
		return segments;
	}

	static function normalizeTargets(values:Array<String>, rustTarget:Null<String>, pos:Position):Array<String> {
		if (values.length == 0)
			return fail(RustDiagnosticId.MetadataValue, "`@:rustSupportCrate.targets` must not be empty.", pos);
		if (values.length == 1 && values[0] == "*")
			return ["*"];
		if (values.indexOf("*") >= 0)
			return fail(RustDiagnosticId.MetadataValue, "`@:rustSupportCrate.targets` cannot mix `*` with exact target triples.", pos);
		var targets = uniqueSorted(values, "target triple", pos, isCargoTargetTriple);
		if (rustTarget == null || rustTarget.length == 0)
			return fail(RustDiagnosticId.MetadataValue, "A target-specific support crate requires `-D rust_target=<exact-triple>`.", pos);
		if (targets.indexOf(rustTarget) < 0)
			return fail(RustDiagnosticId.MetadataValue, "The active `rust_target` is not admitted by `@:rustSupportCrate.targets`.", pos);
		return targets;
	}

	static function validateNativePrefix(classType:ClassType, crateName:String, pos:Position):Void {
		var nativeEntries:Array<MetadataEntry> = [];
		for (entry in classType.meta.get()) {
			if (entry.name == ":native" || entry.name == "native")
				nativeEntries.push(entry);
		}
		if (nativeEntries.length != 1 || nativeEntries[0].params == null || nativeEntries[0].params.length != 1)
			fail(RustDiagnosticId.MetadataValue, "A support-crate extern requires exactly one constant `@:native` Rust path.", pos);
		var nativeText = readString(nativeEntries[0].params[0]);
		if (nativeText == null)
			fail(RustDiagnosticId.MetadataValue, "A support-crate extern requires exactly one constant `@:native` Rust path.", nativeEntries[0].pos);
		try {
			var path = RustMetadataSyntax.parsePath(nativeText);
			if (path.root != RustPathRoot.PathRelative || path.segmentCount < 2 || path.segmentAt(0).argumentStyle != RustPathSegmentArgumentStyle.PathArgumentsNone
				|| path.segmentAt(0).identifier.name != crateName) {
				fail(RustDiagnosticId.MetadataValue, "The support-crate `@:native` path must start with `" + crateName + "::`.", nativeEntries[0].pos);
			}
		} catch (message:String) {
			fail(RustDiagnosticId.MetadataValue, "Invalid support-crate `@:native` path: " + message, nativeEntries[0].pos);
		}
	}

	static function requireString(expression:Expr, field:String):String {
		var value = readString(expression);
		return value == null ? fail(RustDiagnosticId.MetadataValue, "`@:rustSupportCrate." + field + "` must be a compile-time string.", expression.pos) : value;
	}

	static function requireBool(expression:Expr, field:String):Bool {
		return switch (expression.expr) {
			case EConst(CIdent("true")): true;
			case EConst(CIdent("false")): false;
			case _: fail(RustDiagnosticId.MetadataValue, "`@:rustSupportCrate." + field + "` must be a compile-time bool.", expression.pos);
		};
	}

	static function requireStringArray(expression:Expr, field:String):Array<String> {
		var values = switch (expression.expr) {
			case EArrayDecl(items): items;
			case _: return fail(RustDiagnosticId.MetadataValue, "`@:rustSupportCrate." + field + "` must be an array of strings.", expression.pos);
		};
		var result:Array<String> = [];
		for (value in values) {
			var text = readString(value);
			if (text == null)
				return fail(RustDiagnosticId.MetadataValue, "`@:rustSupportCrate." + field + "` must contain only strings.", value.pos);
			result.push(text);
		}
		return result;
	}

	static function readString(expression:Expr):Null<String> {
		return switch (expression.expr) {
			case EConst(CString(value, _)): value;
			case _: null;
		};
	}

	static function uniqueSorted(values:Array<String>, label:String, pos:Position, validator:String->Bool):Array<String> {
		var result:Array<String> = [];
		for (value in values) {
			if (!validator(value))
				return fail(RustDiagnosticId.MetadataValue, "Invalid support-crate " + label + " `" + value + "`.", pos);
			if (result.indexOf(value) >= 0)
				return fail(RustDiagnosticId.MetadataValue, "Duplicate support-crate " + label + " `" + value + "`.", pos);
			result.push(value);
		}
		result.sort(compareText);
		return result;
	}

	static function isLowerRustIdentifier(value:String):Bool {
		if (value == null || value.length == 0 || value.length > 64 || value == "_" || value == "test" || RustNaming.isKeyword(value))
			return false;
		for (index in 0...value.length) {
			var code = value.charCodeAt(index);
			var lower = code >= "a".code && code <= "z".code;
			var digit = code >= "0".code && code <= "9".code;
			if (!lower && code != "_".code && !(digit && index > 0))
				return false;
		}
		return true;
	}

	static function isCargoPackageName(value:String):Bool {
		if (value == null || value.length == 0 || value.length > 64)
			return false;
		for (index in 0...value.length) {
			var code = value.charCodeAt(index);
			var lower = code >= "a".code && code <= "z".code;
			var digit = code >= "0".code && code <= "9".code;
			if (!lower && !digit && code != "_".code && code != "-".code)
				return false;
			if (index == 0 && !lower)
				return false;
		}
		var last = value.charCodeAt(value.length - 1);
		return (last >= "a".code && last <= "z".code) || (last >= "0".code && last <= "9".code);
	}

	static function isCargoFeatureName(value:String):Bool {
		return isCargoPackageName(value);
	}

	static function isExactVersion(value:String):Bool {
		if (!~/^=(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/.match(value))
			return false;
		for (component in value.substr(1).split(".")) {
			if (!decimalFitsCargoVersionComponent(component))
				return false;
		}
		return true;
	}

	static function decimalFitsCargoVersionComponent(value:String):Bool {
		final maximum = "18446744073709551615";
		return value.length < maximum.length || (value.length == maximum.length && value <= maximum);
	}

	static function isCargoTargetTriple(value:String):Bool {
		if (value == null || value.length == 0 || value.indexOf("-") <= 0)
			return false;
		for (index in 0...value.length) {
			var code = value.charCodeAt(index);
			var lower = code >= "a".code && code <= "z".code;
			var digit = code >= "0".code && code <= "9".code;
			if (!lower && !digit && code != "_".code && code != "-".code && code != ".".code)
				return false;
		}
		var segments = value.split("-");
		if (segments.length < 2)
			return false;
		for (segment in segments) {
			if (!isCargoTargetSegment(segment))
				return false;
		}
		return true;
	}

	static function isCargoTargetSegment(value:String):Bool {
		if (value.length == 0 || value.indexOf("..") >= 0)
			return false;
		var first = value.charCodeAt(0);
		var last = value.charCodeAt(value.length - 1);
		return isLowerOrDigit(first) && isLowerOrDigit(last);
	}

	static function isLowerOrDigit(code:Int):Bool {
		return (code >= "a".code && code <= "z".code) || (code >= "0".code && code <= "9".code);
	}

	static function rejectFieldPlacement(field:ClassField, placement:SupportCratePlacementState):Void {
		if (placement.fields.exists(field))
			return;
		placement.fields.set(field, true);
		rejectMetadataPlacement(field.meta, "a field");
		rejectTypeParameterPlacements(field.params, placement);
		rejectTypeFieldPlacement(field.type, placement);
		var expression = field.expr();
		if (expression != null)
			rejectExpressionPlacement(expression, placement);
		var overloads = field.overloads.get();
		for (overloadField in overloads)
			rejectFieldPlacement(overloadField, placement);
	}

	static function rejectTypeMemberPlacement(field:ClassField, placement:SupportCratePlacementState):Void {
		if (placement.fields.exists(field))
			return;
		placement.fields.set(field, true);
		rejectMetadataPlacement(field.meta, "a field");
		rejectTypeParameterPlacements(field.params, placement);
		rejectTypeFieldPlacement(field.type, placement);
		for (overloadField in field.overloads.get())
			rejectTypeMemberPlacement(overloadField, placement);
	}

	static function rejectExpressionPlacement(expression:TypedExpr, placement:SupportCratePlacementState):Void {
		var visitedExpressions:ObjectMap<TypedExpr, Bool> = new ObjectMap();
		var visitedVariables:Map<Int, Bool> = [];
		rejectExpressionPlacementInner(expression, placement, visitedExpressions, visitedVariables);
	}

	static function rejectExpressionPlacementInner(expression:TypedExpr, placement:SupportCratePlacementState,
		visitedExpressions:ObjectMap<TypedExpr, Bool>, visitedVariables:Map<Int, Bool>):Void {
		if (visitedExpressions.exists(expression))
			return;
		visitedExpressions.set(expression, true);
		rejectTypeFieldPlacement(expression.t, placement);
		switch (expression.expr) {
			case TVar(variable, _):
				rejectVariablePlacement(variable, placement, visitedExpressions, visitedVariables);
			case TLocal(variable):
				rejectVariablePlacement(variable, placement, visitedExpressions, visitedVariables);
			case TFor(variable, _, _):
				rejectVariablePlacement(variable, placement, visitedExpressions, visitedVariables);
			case TTry(_, catches):
				for (caught in catches)
					rejectVariablePlacement(caught.v, placement, visitedExpressions, visitedVariables);
			case TFunction(functionValue):
				rejectTypeFieldPlacement(functionValue.t, placement);
				for (argument in functionValue.args) {
					rejectVariablePlacement(argument.v, placement, visitedExpressions, visitedVariables);
					if (argument.value != null)
						rejectExpressionPlacementInner(argument.value, placement, visitedExpressions, visitedVariables);
				}
			case TMeta(metadata, _):
				if (isSupportMetadata(metadata.name))
					fail(RustDiagnosticId.MetadataPlacement, "`@:rustSupportCrate` cannot appear on an expression.", metadata.pos);
			case _:
		}
		TypedExprTools.iter(expression,
			child -> rejectExpressionPlacementInner(child, placement, visitedExpressions, visitedVariables));
	}

	static function rejectVariablePlacement(variable:TVar, placement:SupportCratePlacementState, visitedExpressions:ObjectMap<TypedExpr, Bool>,
		visitedVariables:Map<Int, Bool>):Void {
		if (visitedVariables.exists(variable.id))
			return;
		visitedVariables.set(variable.id, true);
		rejectMetadataPlacement(variable.meta, "a local variable or function argument");
		rejectTypeFieldPlacement(variable.t, placement);
		if (variable.extra != null) {
			rejectTypeParameterPlacements(variable.extra.params, placement);
			if (variable.extra.expr != null)
				rejectExpressionPlacementInner(variable.extra.expr, placement, visitedExpressions, visitedVariables);
		}
	}

	static function rejectTypeParameterPlacements(parameters:Array<TypeParameter>, placement:SupportCratePlacementState):Void {
		for (parameter in parameters) {
			switch (parameter.t) {
				case TInst(classRef, _):
					var classType = classRef.get();
					rejectMetadataPlacement(classType.meta, "a type parameter");
					switch (classType.kind) {
						case KTypeParameter(constraints):
							for (constraint in constraints)
								rejectTypeFieldPlacement(constraint, placement);
						case _:
					}
				case _:
			}
			if (parameter.defaultType != null)
				rejectTypeFieldPlacement(parameter.defaultType, placement);
		}
	}

	static function rejectTypeFieldPlacement(type:Type, placement:SupportCratePlacementState):Void {
		switch (type) {
		case TAnonymous(anonymousRef):
				var anonymousType = anonymousRef.get();
				if (placement.anonymousTypes.exists(anonymousType))
					return;
				placement.anonymousTypes.set(anonymousType, true);
				for (field in anonymousType.fields)
					rejectTypeMemberPlacement(field, placement);
			case TFun(arguments, result):
				for (argument in arguments)
					rejectTypeFieldPlacement(argument.t, placement);
				rejectTypeFieldPlacement(result, placement);
			case TInst(classRef, parameters):
				var classType = classRef.get();
				switch (classType.kind) {
					case KTypeParameter(_):
						// Constraints belong to the type-parameter declaration. Reopening
						// them from an occurrence can recurse forever for F-bounds such as
						// `T:Comparable<T>` because Haxe can return fresh wrappers for T.
						rejectMetadataPlacement(classType.meta, "a type parameter");
					case KGenericInstance(_, genericParameters):
						for (parameter in genericParameters)
							rejectTypeFieldPlacement(parameter, placement);
					case _:
				}
				for (parameter in parameters)
					rejectTypeFieldPlacement(parameter, placement);
			case TEnum(_, parameters) | TType(_, parameters) | TAbstract(_, parameters):
				for (parameter in parameters)
					rejectTypeFieldPlacement(parameter, placement);
			case TDynamic(inner) if (inner != null && inner != type): rejectTypeFieldPlacement(inner, placement);
			case TLazy(resolve):
				var resolved = resolve();
				if (resolved != type)
					rejectTypeFieldPlacement(resolved, placement);
			case TMono(monomorph):
				var inner = monomorph.get();
				if (inner != null && inner != type)
					rejectTypeFieldPlacement(inner, placement);
			case _:
		}
	}

	static function rejectMetadataPlacement(meta:MetaAccess, owner:String):Void {
		if (meta == null)
			return;
		for (entry in meta.get()) {
			if (isSupportMetadata(entry.name))
				fail(RustDiagnosticId.MetadataPlacement, "`@:rustSupportCrate` cannot appear on " + owner + "; it can appear only on an extern class.", entry.pos);
		}
	}

	static function isSupportMetadata(name:String):Bool {
		return name == "rustSupportCrate" || name == ":rustSupportCrate";
	}

	static function compareRequests(left:SupportCrateRequest, right:SupportCrateRequest):Int {
		return compareText(left.name, right.name);
	}

	static function compareDependencies(left:SupportCrateRegistryDependency, right:SupportCrateRegistryDependency):Int {
		return compareText(left.name, right.name);
	}

	static function compareText(left:String, right:String):Int {
		return left < right ? -1 : left > right ? 1 : 0;
	}

	static function fail<T>(id:RustDiagnosticId, detail:String, pos:Position):T {
		throw new SupportCratePlanningFailure(id, detail, pos);
	}
}
#end
