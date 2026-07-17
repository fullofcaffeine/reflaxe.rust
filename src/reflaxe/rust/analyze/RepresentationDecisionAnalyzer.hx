package reflaxe.rust.analyze;

import haxe.io.Path;
import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;
import reflaxe.rust.analyze.RepresentationPlan.RustDecisionOrigin;
import reflaxe.rust.analyze.RepresentationPlan.RustRepresentationDecision;
import reflaxe.rust.analyze.RepresentationPlan.RustSourceValueKind;

/**
	Collects representation decisions from user-authored typed AST.

	Why
	- Runtime and no-hxrt analysis used to recognize arrays, dynamic values, and anonymous objects with
	  their own switches, independently from type lowering.
	- A module-path list cannot explain value-level identity, reuse, nullability, or the source span that
	  caused a runtime requirement.

	What
	- Visits executable field bodies plus declared value/parameter/return and enum-payload types, then asks
	  `RepresentationTypeAnalyzer` for every modeled family.
	- Adds one syntax-refined anonymous-object decision when Haxe has already coerced the literal's
	  result type to `Dynamic`.

	How
	- Field-root `TFunction` nodes describe methods, not first-class function values, so only their
	  parameters, result, and body are visited. Nested `TFunction` nodes remain real function values.
	- Origins retain exact byte offsets while absolute classpath filenames become stable logical paths.
	- Results are de-duplicated and sorted by the planner's canonical key.
**/
class RepresentationDecisionAnalyzer {
	public static function collect(moduleTypes:Array<ModuleType>, nullableStringCompat:Bool,
			?classHasSubclasses:ClassType->Bool):Array<RustRepresentationDecision> {
		var out:Array<RustRepresentationDecision> = [];
		var seen:Map<String, Bool> = [];
		if (moduleTypes == null)
			return out;

		function addDecision(decision:Null<RustRepresentationDecision>):Void {
			if (decision == null)
				return;
			var key = decision.canonicalKey();
			if (seen.exists(key))
				return;
			seen.set(key, true);
			out.push(decision);
		}

		function addType(modulePath:String, label:String, type:Type, pos:haxe.macro.Expr.Position):Void {
			if (type == null || pos == null)
				return;
			var origin = originAt(modulePath, pos);
			if (origin == null)
				return;
			var info = Context.getPosInfos(pos);
			var seenTypes:Map<String, Bool> = [];
			function visitType(current:Type, currentLabel:String):Void {
				if (current == null)
					return;
				var typeKey = TypeTools.toString(current);
				if (seenTypes.exists(typeKey))
					return;
				seenTypes.set(typeKey, true);
				var subject = modulePath + "#" + currentLabel + "@" + info.min + ":" + info.max;
				addDecision(RepresentationTypeAnalyzer.tryDecide(subject, current, pos, origin, nullableStringCompat, null, classHasSubclasses));
				var children = directTypeChildren(current);
				for (index in 0...children.length)
					visitType(children[index], currentLabel + "-type-" + index);
			}
			visitType(type, label);
		}

		function scanExpr(modulePath:String, root:TypedExpr, fieldRoot:Bool):Void {
			function visit(expr:TypedExpr, rootFunction:Bool, suppressCurrent:Bool):Void {
				if (expr == null)
					return;
				var current = unwrapMetaParen(expr);
				var functionNode = switch (current.expr) {
					case TFunction(_): true;
					case _: false;
				};
				var valueBearing = switch (current.expr) {
					case TConst(_) | TLocal(_) | TArray(_, _) | TBinop(_, _, _) | TField(_, _) | TArrayDecl(_) | TCall(_, _) | TNew(_, _, _)
						| TUnop(_, _, _) | TFunction(_) | TCast(_, _) | TObjectDecl(_):
						true;
					case _:
						false;
				};
				if (!suppressCurrent && valueBearing && !(rootFunction && functionNode))
					addType(modulePath, "expr", current.t, current.pos);

				switch (current.expr) {
					case TFunction(fn):
						for (index in 0...fn.args.length)
							addType(modulePath, "function-arg-" + index, fn.args[index].v.t, current.pos);
						addType(modulePath, "function-result", fn.t, current.pos);
						visit(fn.expr, false, false);
						return;
					case TCall(callTarget, arguments):
						var directMethodTarget = switch (unwrapMetaParen(callTarget).expr) {
							case TField(_, FStatic(_, fieldRef)) | TField(_, FInstance(_, _, fieldRef)):
								var field = fieldRef.get();
								field != null && switch (field.kind) {
									case FMethod(_): true;
									case _: false;
								};
							case _: false;
						};
						visit(callTarget, false, directMethodTarget);
						for (argument in arguments)
							visit(argument, false, false);
						return;
					case TVar(variable, initializer):
						if (variable != null)
							addType(modulePath, "local-" + variable.id, variable.t, current.pos);
					case TObjectDecl(_) if (RepresentationTypeAnalyzer.classify(current.t, nullableStringCompat, classHasSubclasses)
						== RustSourceValueKind.SourceDynamic):
						var origin = originAt(modulePath, current.pos);
						if (origin != null) {
							var info = Context.getPosInfos(current.pos);
							addDecision(RepresentationTypeAnalyzer.decideSourceKind(modulePath + "#anonymous-object@" + info.min + ":" + info.max,
								RustSourceValueKind.SourceAnonymousObject, false, origin));
						}
					case _:
				}
				TypedExprTools.iter(current, child -> visit(child, false, false));
			}
			visit(root, fieldRoot, false);
		}

		function scanFields(modulePath:String, fields:Array<ClassField>):Void {
			if (fields == null)
				return;
			for (field in fields) {
				if (field == null)
					continue;
				var method = switch (field.kind) {
					case FMethod(_): true;
					case _: false;
				};
				switch (field.type) {
					case TFun(parameters, result) if (method):
						for (index in 0...parameters.length)
							addType(modulePath, field.name + "-parameter-" + index, parameters[index].t, field.pos);
						addType(modulePath, field.name + "-result", result, field.pos);
					case _:
						addType(modulePath, "field-" + field.name, field.type, field.pos);
				}
				var expression = field.expr();
				if (expression != null)
					scanExpr(modulePath, expression, method);
			}
		}

		for (moduleType in moduleTypes) {
			switch (moduleType) {
				case TClassDecl(classRef):
					var classType = classRef.get();
					if (classType != null) {
						var modulePath = moduleName(classType.module, classType.pack, classType.name);
						scanFields(modulePath, classType.fields.get());
						scanFields(modulePath, classType.statics.get());
					}
				case TAbstract(abstractRef):
					var abstractType = abstractRef.get();
					if (abstractType != null && abstractType.impl != null) {
						var implementation = abstractType.impl.get();
						if (implementation != null) {
							var modulePath = moduleName(abstractType.module, abstractType.pack, abstractType.name);
							scanFields(modulePath, implementation.fields.get());
							scanFields(modulePath, implementation.statics.get());
						}
					}
				case TEnumDecl(enumRef):
					var enumType = enumRef.get();
					if (enumType != null) {
						var modulePath = moduleName(enumType.module, enumType.pack, enumType.name);
						var constructorNames = [for (name in enumType.constructs.keys()) name];
						constructorNames.sort(compareStrings);
						for (constructorName in constructorNames) {
							var constructor = enumType.constructs.get(constructorName);
							if (constructor == null)
								continue;
							switch (constructor.type) {
								case TFun(parameters, _):
									for (index in 0...parameters.length)
										addType(modulePath, "enum-" + constructorName + "-parameter-" + index, parameters[index].t, constructor.pos);
								case _:
							}
						}
					}
				case TTypeDecl(_):
			}
		}

		out.sort((left, right) -> compareStrings(left.canonicalKey(), right.canonicalKey()));
		return out;
	}

	/**
		Returns the direct representation-bearing children of one typed value.

		Why / What / How
		- Rust lowering recursively maps container arguments, function signatures, anonymous fields, and
		  typedef targets. Ignoring those children can call `rust.Vec<Dynamic>` no-runtime even though its
		  element still emits the hxrt Dynamic carrier.
		- This helper follows only structural storage edges, not class fields or method declarations, so it
		  does not turn compiler type scaffolding into invented runtime values.
		- The caller owns cycle suppression and canonical decision sorting.
	**/
	static function directTypeChildren(type:Type):Array<Type> {
		var out:Array<Type> = [];
		switch (type) {
			case TMono(monomorphRef):
				var resolved = monomorphRef.get();
				if (resolved != null)
					out.push(resolved);
			case TEnum(_, parameters) | TInst(_, parameters) | TAbstract(_, parameters):
				if (parameters != null)
					for (parameter in parameters)
						out.push(parameter);
			case TType(typeRef, parameters):
				var typedefType = typeRef.get();
				if (typedefType != null) {
					var underlying = typedefType.type;
					if (typedefType.params != null && typedefType.params.length > 0 && parameters.length == typedefType.params.length)
						underlying = TypeTools.applyTypeParameters(underlying, typedefType.params, parameters);
					out.push(underlying);
				}
			case TFun(arguments, result):
				for (argument in arguments)
					out.push(argument.t);
				out.push(result);
			case TAnonymous(anonymousRef):
				var anonymous = anonymousRef.get();
				if (anonymous != null && anonymous.fields != null) {
					var fields = anonymous.fields.copy();
					fields.sort((left, right) -> compareStrings(left.name, right.name));
					for (field in fields)
						out.push(field.type);
				}
			case TDynamic(inner):
				if (inner != null)
					out.push(inner);
			case TLazy(resolve):
				var resolved = resolve();
				if (resolved != null)
					out.push(resolved);
		}
		return out;
	}

	static function originAt(modulePath:String, pos:haxe.macro.Expr.Position):Null<RustDecisionOrigin> {
		var info = Context.getPosInfos(pos);
		if (info == null || info.file == null || info.file.length == 0 || info.min < 0 || info.max < info.min)
			return null;
		var slashed = info.file.split("\\").join("/");
		var stableFile = isSafeRelative(slashed) ? slashed : "classpath/" + modulePath.split(".").join("/") + "/" + Path.withoutDirectory(slashed);
		return RustDecisionOrigin.at(stableFile, info.min, info.max, modulePath);
	}

	static function isSafeRelative(path:String):Bool {
		if (path == null || path.length == 0 || Path.isAbsolute(path) || ~/^[A-Za-z]:/.match(path) || ~/[\x00-\x1f\x7f]/.match(path))
			return false;
		for (segment in path.split("/"))
			if (segment.length == 0 || segment == "." || segment == "..")
				return false;
		return true;
	}

	static function unwrapMetaParen(expr:TypedExpr):TypedExpr {
		var current = expr;
		var changed = true;
		while (changed && current != null) {
			changed = false;
			switch (current.expr) {
				case TMeta(_, inner) | TParenthesis(inner):
					current = inner;
					changed = true;
				case _:
			}
		}
		return current;
	}

	static inline function moduleName(module:String, pack:Array<String>, name:String):String {
		return module != null && module.length > 0 ? module : (pack == null || pack.length == 0 ? name : pack.join(".") + "." + name);
	}

	static inline function compareStrings(left:String, right:String):Int {
		return left < right ? -1 : (left > right ? 1 : 0);
	}
}
