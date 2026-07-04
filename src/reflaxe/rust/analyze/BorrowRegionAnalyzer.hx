package reflaxe.rust.analyze;

import haxe.macro.Expr.Binop;
import haxe.macro.Type;
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;

/**
	BorrowRegionAnalyzer

	Why
	- Scoped helpers such as `rust.Borrow.withRef(...)` and `rust.SliceTools.with(...)`
	  encode Rust-like lexical borrow regions in Haxe.
	- The macro guard catches direct token escapes before typed expansion, but aliases such as
	  `var alias = borrowed; return alias;` need typed-AST tracking.
	- Reporting these mistakes from Haxe source positions avoids deferred Rust lifetime errors in
	  generated code.

	What
	- Tracks local aliases of borrow-only surface types:
	  - `rust.Ref<T>`
	  - `rust.MutRef<T>`
	  - `rust.Slice<T>`
	  - `rust.MutSlice<T>`
	  - `rust.Str`
	- Rejects the first typed escape slice:
	  - returning a borrow alias from a function/block result,
	  - returning wrapper/object/helper-call values that still contain a borrow alias,
	  - throwing a borrow alias or wrapped value that still contains one,
	  - storing a borrow alias into a field/static slot,
	  - storing a closure that captures a borrow alias into a field/static slot,
	  - overlapping scoped mutable borrows of the same local source value.

	How
	- Walks typed expressions with lexical block scopes.
	- Marks locals whose declared or inferred type is one of the borrow-only abstracts.
	- Treats simple local aliases as in-region values, while nested block results and explicit
	  returns are escape positions.
	- Rejects packaged escapes only when the escaped expression type still contains a borrow-only
	  type, so owned derivations such as `Some(VecTools.len(alias))` remain valid.
	- Tracks first-wave mutable borrow regions by local source identity, which catches nested
	  `withMut(...)` / `MutSliceTools.with(...)` conflicts while allowing sequential scoped borrows.
	- Does not attempt full lifetime parity: field/static source provenance and whole-program alias
	  equivalence remain follow-up typed-pass work.
**/
class BorrowRegionAnalyzer {
	public static function analyze(moduleTypes:Array<ModuleType>, shouldReport:haxe.macro.Expr.Position->Bool):BorrowRegionDiagnostics {
		var errors:Array<BorrowRegionDiagnostic> = [];
		var seen = new Map<String, Bool>();

		function add(message:String, pos:haxe.macro.Expr.Position):Void {
			if (!shouldReport(pos))
				return;
			var posInfos = haxe.macro.Context.getPosInfos(pos);
			var key = posInfos.file + ":" + posInfos.min + ":" + posInfos.max + ":" + message;
			if (seen.exists(key))
				return;
			seen.set(key, true);
			errors.push({message: message, pos: pos});
		}

		for (moduleType in moduleTypes) {
			switch (moduleType) {
				case TClassDecl(classRef):
					var classType = classRef.get();
					scanClassFieldExprs(classType.fields.get(), add);
					scanClassFieldExprs(classType.statics.get(), add);
				case _:
			}
		}

		return {errors: errors};
	}

	static function scanClassFieldExprs(fields:Array<ClassField>, add:(String, haxe.macro.Expr.Position) -> Void):Void {
		for (field in fields) {
			var expr = field.expr();
			if (expr == null)
				continue;
			scanExpr(expr, new BorrowRegionEnv(), false, add);
		}
	}

	static function scanExpr(expr:TypedExpr, env:BorrowRegionEnv, escapePosition:Bool, add:(String, haxe.macro.Expr.Position) -> Void):Void {
		if (expr == null)
			return;

		var current = unwrapMetaParen(expr);
		if (escapePosition) {
			var closureCapture = capturedBorrowAliasInClosure(current, env);
			if (closureCapture != null) {
				add("returned closure captures borrow-only alias `"
					+ localName(closureCapture.variable)
					+ "` ("
					+ closureCapture.reason
					+ "). Move owned data into the closure instead of capturing the scoped borrow.",
					current.pos);
				return;
			}

			var escapeReason = borrowReasonOfExpr(current, env);
			if (escapeReason != null) {
				add("returned borrow-only alias `" + escapeReason.name + "` (" + escapeReason.reason
					+ "). Return an owned value derived from the borrow instead.",
					escapeReason.pos);
				return;
			}

			var packagedEscape = packagedBorrowEscapeOfExpr(current, env);
			if (packagedEscape != null) {
				add("returned value packages borrow-only alias `"
					+ packagedEscape.name
					+ "` ("
					+ packagedEscape.reason
					+ "). Return an owned value derived from the borrow instead of wrapping the borrow token.",
					packagedEscape.pos);
				return;
			}
		}

		switch (current.expr) {
			case TFunction(fn):
				scanFunction(fn, add);

			case TBlock(exprs):
				var blockEnv = env.fork();
				for (i in 0...exprs.length)
					scanExpr(exprs[i], blockEnv, escapePosition && i == exprs.length - 1, add);

			case TVar(v, init):
				{
					var generatedHxRefSource = v != null
						&& init != null
						&& StringTools.startsWith(localName(v), "__hx_ref") ? localSourceOfExpr(init) : null;
					var localReason = v == null ? null : classifyBorrowReason(v.t);
					var localContainsBorrow = v != null && typeContainsBorrowReason(v.t);
					if (localReason == null && init != null)
						localReason = classifyBorrowReason(init.t);
					var packagedInit = v != null
						&& init != null
						&& localContainsBorrow
						&& localReason == null ? packagedBorrowEscapeOfExpr(init, env) : null;
					if (init != null) {
						var directAlias = isDirectBorrowAliasInit(init, env);
						var escapesNewBorrowRegion = (localReason != null || localContainsBorrow) && !env.hasBorrowAliases();
						scanExpr(init, env, escapesNewBorrowRegion && !directAlias, add);
					}
					if (v != null && generatedHxRefSource != null) {
						env.addSourceAlias(v, generatedHxRefSource);
					} else if (v != null && localReason != null) {
						var aliasHit = init == null ? null : borrowSourceHitOfAliasInit(init, env);
						var aliasSource = aliasHit == null ? null : aliasHit.source;
						var newMutableSource = init == null
							|| aliasSource != null
							|| !isMutableBorrowReason(localReason) ? null : localSourceOfExpr(init);
						if (newMutableSource != null)
							registerMutableRegion(newMutableSource, localName(v), localReason, current.pos, env, add);
						else if (aliasSource != null && isMutableBorrowReason(localReason)) {
							if (aliasHit != null && aliasHit.fromBorrowAlias && env.findActiveMutable(aliasSource.key) != null)
								env.renameActiveMutable(aliasSource.key, localName(v));
							else
								registerMutableRegion(aliasSource, localName(v), localReason, current.pos, env, add);
						}
						var source = aliasSource != null ? aliasSource : newMutableSource;
						env.add(v, localReason, current.pos, source);
					} else if (v != null && packagedInit != null) {
						env.addPackaged(v, packagedInit);
					}
				}

			case TReturn(value):
				if (value != null)
					scanExpr(value, env, true, add);

			case TBinop(OpAssign, left, right):
				{
					if (isStorageTarget(left)) {
						var closureCapture = capturedBorrowAliasInClosure(right, env);
						if (closureCapture != null) {
							add("stored closure captures borrow-only alias `"
								+ localName(closureCapture.variable)
								+ "` ("
								+ closureCapture.reason
								+ "). Closures stored outside the scoped region must capture owned values.",
								right.pos);
						} else {
							var storedReason = borrowReasonOfExpr(right, env);
							if (storedReason != null) {
								add("stored borrow-only alias `"
									+ storedReason.name
									+ "` ("
									+ storedReason.reason
									+ ") in a field/static slot. Keep borrow aliases local to the scoped region.",
									right.pos);
							} else {
								var packagedStored = packagedBorrowEscapeOfExpr(right, env);
								if (packagedStored != null) {
									add("stored value packages borrow-only alias `"
										+ packagedStored.name
										+ "` ("
										+ packagedStored.reason
										+ ") in a field/static slot. Store owned data derived from the borrow instead.",
										packagedStored.pos);
								}
							}
						}
					}
					scanExpr(left, env, false, add);
					scanExpr(right, env, false, add);
				}

			case TBinop(_, left, right):
				{
					scanExpr(left, env, false, add);
					scanExpr(right, env, false, add);
				}

			case TCall(callTarget, args):
				if (!scanMutableRegionCall(callTarget, args, env, add)) {
					scanExpr(callTarget, env, false, add);
					for (arg in args)
						scanExpr(arg, env, false, add);
				}

			case TIf(condition, ifExpr, elseExpr):
				{
					scanExpr(condition, env, false, add);
					scanExpr(ifExpr, env, escapePosition, add);
					if (elseExpr != null)
						scanExpr(elseExpr, env, escapePosition, add);
				}

			case TSwitch(subject, cases, defaultExpr):
				{
					scanExpr(subject, env, false, add);
					for (caseExpr in cases) {
						for (value in caseExpr.values)
							scanExpr(value, env, false, add);
						scanExpr(caseExpr.expr, env, escapePosition, add);
					}
					if (defaultExpr != null)
						scanExpr(defaultExpr, env, escapePosition, add);
				}

			case TTry(tryExpr, catches):
				{
					scanExpr(tryExpr, env, escapePosition, add);
					for (catchExpr in catches) {
						var catchEnv = env.fork();
						if (catchExpr.v != null) {
							var catchReason = classifyBorrowReason(catchExpr.v.t);
							if (catchReason != null)
								catchEnv.add(catchExpr.v, catchReason, current.pos, null);
						}
						scanExpr(catchExpr.expr, catchEnv, escapePosition, add);
					}
				}

			case TFor(v, it, body):
				{
					scanExpr(it, env, false, add);
					var loopEnv = env.fork();
					var loopReason = v == null ? null : classifyBorrowReason(v.t);
					if (v != null && loopReason != null)
						loopEnv.add(v, loopReason, current.pos, null);
					scanExpr(body, loopEnv, false, add);
				}

			case TWhile(condition, body, _):
				{
					scanExpr(condition, env, false, add);
					scanExpr(body, env.fork(), false, add);
				}

			case TThrow(value):
				{
					var thrownReason = borrowReasonOfExpr(value, env);
					if (thrownReason != null) {
						add("thrown borrow-only alias `"
							+ thrownReason.name
							+ "` ("
							+ thrownReason.reason
							+ "). Throw owned error data instead of a scoped borrow token.",
							thrownReason.pos);
					} else {
						var packagedThrow = packagedBorrowEscapeOfExpr(value, env);
						if (packagedThrow != null)
							add("thrown value packages borrow-only alias `"
								+ packagedThrow.name
								+ "` ("
								+ packagedThrow.reason
								+ "). Throw owned error data instead of wrapping the scoped borrow token.",
								packagedThrow.pos);
					}
					scanExpr(value, env, false, add);
				}

			case TMeta(_, inner) | TParenthesis(inner) | TCast(inner, _):
				scanExpr(inner, env, escapePosition, add);

			case _:
				TypedExprTools.iter(current, child -> scanExpr(child, env, false, add));
		}
	}

	static function scanFunction(fn:TFunc, add:(String, haxe.macro.Expr.Position) -> Void):Void {
		if (fn == null || fn.expr == null)
			return;

		var fnEnv = new BorrowRegionEnv();
		scanFunctionWithEnv(fn, fnEnv, null, add);
	}

	static function scanFunctionWithEnv(fn:TFunc, fnEnv:BorrowRegionEnv, argSources:Null<Array<Null<BorrowSourceInfo>>>,
			add:(String, haxe.macro.Expr.Position) -> Void):Void {
		if (fn.args != null) {
			for (i in 0...fn.args.length) {
				var arg = fn.args[i];
				if (arg == null || arg.v == null)
					continue;
				var reason = classifyBorrowReason(arg.v.t);
				if (reason != null)
					fnEnv.add(arg.v, reason, fn.expr.pos, argSources != null && i < argSources.length ? argSources[i] : null);
			}
		}
		scanExpr(fn.expr, fnEnv, true, add);
	}

	static function scanMutableRegionCall(callTarget:TypedExpr, args:Array<TypedExpr>, env:BorrowRegionEnv,
			add:(String, haxe.macro.Expr.Position) -> Void):Bool {
		var spec = resolveMutableRegionCall(callTarget);
		if (spec == null || args == null || args.length < 2)
			return false;

		scanExpr(callTarget, env, false, add);
		scanExpr(args[0], env, false, add);

		var source = localSourceOfExpr(args[0]);
		var callback = unwrapMetaParenCast(args[1]);
		switch (callback.expr) {
			case TFunction(fn):
				if (source != null) {
					var callEnv = env.fork();
					registerMutableRegion(source, spec.borrowerLabel, spec.borrowReason, callback.pos, callEnv, add);
					scanFunctionWithEnv(fn, callEnv, [source], add);
				} else {
					scanExpr(args[1], env, false, add);
				}
			case _:
				scanExpr(args[1], env, false, add);
		}

		if (args.length > 2) {
			for (i in 2...args.length)
				scanExpr(args[i], env, false, add);
		}
		return true;
	}

	static function resolveMutableRegionCall(callTarget:TypedExpr):Null<MutableRegionCallSpec> {
		var current = unwrapMetaParenCast(callTarget);
		return switch (current.expr) {
			case TField(_, FStatic(ownerRef, fieldRef)):
				{
					var owner = ownerRef.get();
					var field = fieldRef.get();
					var ownerPath = owner == null ? "" : modulePath(owner.pack, owner.name);
					var method = field == null ? "" : field.name;
					if (ownerPath == "rust.ArrayBorrow" && method == "withMutSlice")
						{borrowerLabel: "mutable slice callback", borrowReason: "rust.MutSlice<T>"} else
						null;
				}
			case _:
				null;
		}
	}

	static function registerMutableRegion(source:BorrowSourceInfo, borrowerName:String, reason:String, pos:haxe.macro.Expr.Position, env:BorrowRegionEnv,
			add:(String, haxe.macro.Expr.Position) -> Void):Void {
		var active = env.findActiveMutable(source.key);
		if (active != null) {
			add("overlapping mutable borrow of `"
				+ source.label
				+ "` through `"
				+ borrowerName
				+ "` ("
				+ reason
				+ ") while `"
				+ active.borrowerName
				+ "` is still active. End the first scoped mutable borrow before starting another.",
				pos);
		}
		env.addActiveMutable({
			source: source,
			borrowerName: borrowerName,
			reason: reason,
			pos: pos
		});
	}

	static function isStorageTarget(expr:TypedExpr):Bool {
		var current = unwrapMetaParenCast(expr);
		return switch (current.expr) {
			case TField(_, _) | TArray(_, _):
				true;
			case _:
				false;
		}
	}

	static function isDirectBorrowAliasInit(expr:TypedExpr, env:BorrowRegionEnv):Bool {
		var current = unwrapMetaParenCast(expr);
		return switch (current.expr) {
			case TLocal(variable): var alias = variable == null ? null : env.resolve(variable.id); alias != null || classifyBorrowReason(current.t) != null;
			case _:
				false;
		}
	}

	static function borrowSourceHitOfAliasInit(expr:TypedExpr, env:BorrowRegionEnv):Null<BorrowSourceHit> {
		var current = unwrapMetaParenCast(expr);
		return switch (current.expr) {
			case TLocal(variable):
				{
					var alias = variable == null ? null : env.resolve(variable.id);
					if (alias != null && alias.source != null)
						{source: alias.source, fromBorrowAlias: true} else {
						var source = variable == null ? null : env.resolveSourceAlias(variable.id);
						source == null ? null : {source: source, fromBorrowAlias: false};
					}
				}
			case _:
				null;
		}
	}

	static function localSourceOfExpr(expr:TypedExpr):Null<BorrowSourceInfo> {
		var current = unwrapMetaParenCast(expr);
		return switch (current.expr) {
			case TLocal(variable):
				var name = localName(variable);
				{key: "local:" + variable.id, label: name, pos: current.pos};
			case _:
				null;
		}
	}

	static function borrowReasonOfExpr(expr:TypedExpr, env:BorrowRegionEnv):Null<BorrowEscapeReason> {
		var current = unwrapMetaParenCast(expr);
		return switch (current.expr) {
			case TLocal(variable):
				{
					var alias = variable == null ? null : env.resolve(variable.id);
					if (alias != null)
						{name: localName(variable), reason: alias.reason, pos: alias.pos} else {
						var typeReason = classifyBorrowReason(current.t);
						typeReason == null ? null : {name: localName(variable), reason: typeReason, pos: current.pos};
					}
				}
			case _:
				null;
		}
	}

	static function packagedBorrowEscapeOfExpr(expr:TypedExpr, env:BorrowRegionEnv):Null<BorrowEscapeReason> {
		var current = unwrapMetaParenCast(expr);
		switch (current.expr) {
			case TBlock(exprs):
				return exprs.length == 0 ? null : packagedBorrowEscapeOfExpr(exprs[exprs.length - 1], env);
			case TIf(_, _, _) | TSwitch(_, _, _) | TTry(_, _) | TReturn(_) | TThrow(_):
				return null;
			case _:
		}
		if (!typeContainsBorrowReason(current.t))
			return null;
		return firstBorrowAliasReference(current, env);
	}

	static function firstBorrowAliasReference(root:TypedExpr, env:BorrowRegionEnv):Null<BorrowEscapeReason> {
		var first:Null<BorrowEscapeReason> = null;

		function visit(expr:TypedExpr):Void {
			if (first != null || expr == null)
				return;
			var current = unwrapMetaParen(expr);
			switch (current.expr) {
				case TFunction(_):
					return;
				case TLocal(variable):
					{
						var alias = variable == null ? null : env.resolve(variable.id);
						if (alias != null) {
							first = {name: localName(variable), reason: alias.reason, pos: current.pos};
							return;
						}
						var packaged = variable == null ? null : env.resolvePackaged(variable.id);
						if (packaged != null) {
							first = packaged;
							return;
						}
					}
				case _:
			}
			TypedExprTools.iter(current, visit);
		}

		visit(root);
		return first;
	}

	static function capturedBorrowAliasInClosure(expr:TypedExpr, env:BorrowRegionEnv):Null<CapturedBorrowAlias> {
		var current = unwrapMetaParenCast(expr);
		return switch (current.expr) {
			case TFunction(fn):
				firstBorrowAliasCapture(fn, env);
			case _:
				null;
		}
	}

	static function firstBorrowAliasCapture(fn:TFunc, env:BorrowRegionEnv):Null<CapturedBorrowAlias> {
		if (fn == null || fn.expr == null)
			return null;

		var declared = collectDeclaredLocalIds(fn);
		var first:Null<CapturedBorrowAlias> = null;

		function visit(expr:TypedExpr):Void {
			if (first != null || expr == null)
				return;
			var current = unwrapMetaParen(expr);
			switch (current.expr) {
				case TLocal(variable):
					if (variable != null && !declared.exists(variable.id)) {
						var alias = env.resolve(variable.id);
						if (alias != null)
							first = {variable: variable, reason: alias.reason, pos: current.pos};
					}
				case _:
			}
			TypedExprTools.iter(current, visit);
		}

		visit(fn.expr);
		return first;
	}

	static function collectDeclaredLocalIds(fn:TFunc):Map<Int, Bool> {
		var declared = new Map<Int, Bool>();
		if (fn.args != null) {
			for (arg in fn.args) {
				if (arg != null && arg.v != null)
					declared.set(arg.v.id, true);
			}
		}

		function visit(expr:TypedExpr):Void {
			var current = unwrapMetaParen(expr);
			switch (current.expr) {
				case TVar(v, init):
					{
						if (v != null)
							declared.set(v.id, true);
						if (init != null)
							visit(init);
					}
				case TFor(v, it, body):
					{
						if (v != null)
							declared.set(v.id, true);
						visit(it);
						visit(body);
					}
				case TTry(tryExpr, catches):
					{
						visit(tryExpr);
						for (catchExpr in catches) {
							if (catchExpr != null && catchExpr.v != null)
								declared.set(catchExpr.v.id, true);
							if (catchExpr != null && catchExpr.expr != null)
								visit(catchExpr.expr);
						}
					}
				case TFunction(inner):
					{
						if (inner != null && inner.args != null) {
							for (arg in inner.args) {
								if (arg != null && arg.v != null)
									declared.set(arg.v.id, true);
							}
						}
						if (inner != null && inner.expr != null)
							visit(inner.expr);
					}
				case _:
					TypedExprTools.iter(current, visit);
			}
		}

		visit(fn.expr);
		return declared;
	}

	static function classifyBorrowReason(t:Type):Null<String> {
		return classifyBorrowReasonRecursive(t, 0);
	}

	static function isMutableBorrowReason(reason:String):Bool {
		return reason == "rust.MutRef<T>" || reason == "rust.MutSlice<T>";
	}

	static function typeContainsBorrowReason(t:Type):Bool {
		return typeContainsBorrowReasonRecursive(t, 0);
	}

	static function typeContainsBorrowReasonRecursive(t:Type, depth:Int):Bool {
		if (t == null || depth > 16)
			return false;
		if (classifyBorrowReasonRecursive(t, depth) != null)
			return true;

		return switch (t) {
			case TMono(monoRef): var resolved = monoRef.get(); resolved != null && typeContainsBorrowReasonRecursive(resolved, depth + 1);
			case TLazy(loader):
				typeContainsBorrowReasonRecursive(loader(), depth + 1);
			case TType(_, _):
				typeContainsBorrowReasonRecursive(TypeTools.follow(t), depth + 1);
			case TAbstract(_, params) | TInst(_, params) | TEnum(_, params): params != null && containsBorrowInTypeList(params, depth + 1);
			case TAnonymous(anonRef):
				{
					var anon = anonRef.get();
					if (anon == null || anon.fields == null)
						false;
					else {
						var found = false;
						for (field in anon.fields) {
							if (field != null && typeContainsBorrowReasonRecursive(field.type, depth + 1)) {
								found = true;
								break;
							}
						}
						found;
					}
				}
			case TFun(args, ret):
				{
					var found = typeContainsBorrowReasonRecursive(ret, depth + 1);
					if (!found && args != null) {
						for (arg in args) {
							if (arg != null && typeContainsBorrowReasonRecursive(arg.t, depth + 1)) {
								found = true;
								break;
							}
						}
					}
					found;
				}
			case _:
				false;
		}
	}

	static function containsBorrowInTypeList(types:Array<Type>, depth:Int):Bool {
		for (param in types) {
			if (typeContainsBorrowReasonRecursive(param, depth))
				return true;
		}
		return false;
	}

	static function classifyBorrowReasonRecursive(t:Type, depth:Int):Null<String> {
		if (t == null || depth > 16)
			return null;

		return switch (t) {
			case TMono(monoRef):
				var resolved = monoRef.get();
				resolved == null ? null : classifyBorrowReasonRecursive(resolved, depth + 1);
			case TLazy(loader):
				classifyBorrowReasonRecursive(loader(), depth + 1);
			case TType(_, _):
				classifyBorrowReasonRecursive(TypeTools.follow(t), depth + 1);
			case TAbstract(absRef, params):
				var abs = absRef.get();
				var path = modulePath(abs.pack, abs.name);
				switch (path) {
					case "rust.Ref":
						"rust.Ref<T>";
					case "rust.MutRef":
						"rust.MutRef<T>";
					case "rust.Slice":
						"rust.Slice<T>";
					case "rust.MutSlice":
						"rust.MutSlice<T>";
					case "rust.Str":
						"rust.Str";
					case "Null":
						if (params != null && params.length == 1) classifyBorrowReasonRecursive(params[0], depth + 1) else null;
					case _:
						null;
				}
			case _:
				null;
		}
	}

	static inline function modulePath(pack:Array<String>, name:String):String {
		return pack == null || pack.length == 0 ? name : pack.join(".") + "." + name;
	}

	static function unwrapMetaParen(expr:TypedExpr):TypedExpr {
		var current = expr;
		while (true) {
			switch (current.expr) {
				case TMeta(_, inner):
					current = inner;
					continue;
				case TParenthesis(inner):
					current = inner;
					continue;
				case _:
			}
			break;
		}
		return current;
	}

	static function unwrapMetaParenCast(expr:TypedExpr):TypedExpr {
		var current = expr;
		while (true) {
			switch (current.expr) {
				case TMeta(_, inner):
					current = inner;
					continue;
				case TParenthesis(inner):
					current = inner;
					continue;
				case TCast(inner, _):
					current = inner;
					continue;
				case _:
			}
			break;
		}
		return current;
	}

	static function localName(variable:TVar):String {
		if (variable == null)
			return "local";
		return variable.name == null || variable.name.length == 0 ? "local#" + variable.id : variable.name;
	}
}

private class BorrowRegionEnv {
	final parent:Null<BorrowRegionEnv>;
	final aliases:Map<Int, BorrowAliasInfo>;
	final packagedAliases:Map<Int, BorrowEscapeReason>;
	final sourceAliases:Map<Int, BorrowSourceInfo>;
	final activeMutable:Array<MutableRegionInfo>;

	public function new(?parent:BorrowRegionEnv) {
		this.parent = parent;
		this.aliases = new Map<Int, BorrowAliasInfo>();
		this.packagedAliases = new Map<Int, BorrowEscapeReason>();
		this.sourceAliases = new Map<Int, BorrowSourceInfo>();
		this.activeMutable = [];
	}

	public function fork():BorrowRegionEnv {
		return new BorrowRegionEnv(this);
	}

	public function add(variable:TVar, reason:String, pos:haxe.macro.Expr.Position, source:Null<BorrowSourceInfo>):Void {
		aliases.set(variable.id, {
			variable: variable,
			reason: reason,
			pos: pos,
			source: source
		});
	}

	public function resolve(id:Int):Null<BorrowAliasInfo> {
		var local = aliases.get(id);
		if (local != null)
			return local;
		return parent == null ? null : parent.resolve(id);
	}

	public function addPackaged(variable:TVar, reason:BorrowEscapeReason):Void {
		packagedAliases.set(variable.id, reason);
	}

	public function resolvePackaged(id:Int):Null<BorrowEscapeReason> {
		var local = packagedAliases.get(id);
		if (local != null)
			return local;
		return parent == null ? null : parent.resolvePackaged(id);
	}

	public function hasBorrowAliases():Bool {
		for (_ in aliases.keys())
			return true;
		return parent != null && parent.hasBorrowAliases();
	}

	public function addSourceAlias(variable:TVar, source:BorrowSourceInfo):Void {
		sourceAliases.set(variable.id, source);
	}

	public function resolveSourceAlias(id:Int):Null<BorrowSourceInfo> {
		var local = sourceAliases.get(id);
		if (local != null)
			return local;
		return parent == null ? null : parent.resolveSourceAlias(id);
	}

	public function addActiveMutable(region:MutableRegionInfo):Void {
		activeMutable.push(region);
	}

	public function findActiveMutable(sourceKey:String):Null<MutableRegionInfo> {
		for (region in activeMutable) {
			if (region.source.key == sourceKey)
				return region;
		}
		return parent == null ? null : parent.findActiveMutable(sourceKey);
	}

	public function renameActiveMutable(sourceKey:String, borrowerName:String):Void {
		for (region in activeMutable) {
			if (region.source.key == sourceKey) {
				region.borrowerName = borrowerName;
				return;
			}
		}
		if (parent != null)
			parent.renameActiveMutable(sourceKey, borrowerName);
	}
}

private typedef BorrowAliasInfo = {
	var variable:TVar;
	var reason:String;
	var pos:haxe.macro.Expr.Position;
	var source:Null<BorrowSourceInfo>;
};

private typedef BorrowSourceInfo = {
	var key:String;
	var label:String;
	var pos:haxe.macro.Expr.Position;
};

private typedef BorrowSourceHit = {
	var source:BorrowSourceInfo;
	var fromBorrowAlias:Bool;
};

private typedef MutableRegionInfo = {
	var source:BorrowSourceInfo;
	var borrowerName:String;
	var reason:String;
	var pos:haxe.macro.Expr.Position;
};

private typedef MutableRegionCallSpec = {
	var borrowerLabel:String;
	var borrowReason:String;
};

private typedef BorrowEscapeReason = {
	var name:String;
	var reason:String;
	var pos:haxe.macro.Expr.Position;
};

private typedef CapturedBorrowAlias = {
	var variable:TVar;
	var reason:String;
	var pos:haxe.macro.Expr.Position;
};

/**
	Borrow-region diagnostic emitted by `BorrowRegionAnalyzer`.

	Why
	- Callers need a small, typed result shape that can be reported through Haxe's normal
	  source-position diagnostics.

	What
	- `message` is the user-facing borrow-region failure without the compiler-level prefix.
	- `pos` is the Haxe source expression that returned, stored, threw, or overlapped the borrow.

	How
	- `RustCompiler.enforceBorrowRegionContracts()` adds the stable
	  `Rust borrow region violation:` prefix before calling `Context.error(...)`.
**/
typedef BorrowRegionDiagnostic = {
	var message:String;
	var pos:haxe.macro.Expr.Position;
};

/**
	Typed result envelope for scoped borrow-region analysis.

	Why
	- Keeping the analyzer pure and returning diagnostics lets the compiler decide which source
	  files are reportable for the active build.

	What
	- `errors` contains hard contract violations. Escaping a borrow-only token is never downgraded to
	  a warning because generated Rust would be invalid or misleading.

	How
	- The compiler calls `BorrowRegionAnalyzer.analyze(...)` once per build after typed modules are
	  available and reports every returned error at its recorded source position.
**/
typedef BorrowRegionDiagnostics = {
	var errors:Array<BorrowRegionDiagnostic>;
};
