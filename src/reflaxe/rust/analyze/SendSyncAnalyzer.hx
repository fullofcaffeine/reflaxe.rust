package reflaxe.rust.analyze;

import haxe.macro.Type;
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;
import reflaxe.rust.DynamicBoundary;

/**
	SendSyncAnalyzer

	Why
	- Rust thread/task boundaries require captured values to satisfy `Send + Sync` (and often `'static`).
	- When user closures capture borrow-only Haxe surface types (`rust.Ref`, `rust.MutRef`, slices),
	  Rust errors happen later during Cargo compile with diagnostics that point at generated Rust.
	- This analyzer keeps diagnostics in Haxe source positions so users can fix boundaries early.

	What
	- Scans typed Haxe expressions for thread/task spawn callsites:
	  - `sys.thread.Thread.create`
	  - `sys.thread.Thread.createWithEventLoop`
	  - `rust.concurrent.Tasks.spawn`
	  - `rust.async.Tasks.spawn`
	- For inline closure jobs, inspects captured locals and closure return types for known
	  non-sendable boundary types:
	  - `rust.Ref<T>`, `rust.MutRef<T>`
	  - `rust.Slice<T>`, `rust.MutSlice<T>`
	  - `Dynamic` / `TDynamic`
	- Returns typed diagnostics (`warnings`, `errors`) so caller policy can decide strictness.

	How
	- Walk all typed class/static field expressions.
	- Match thread/task APIs by resolved owner path + method name in typed AST (`FStatic`).
	- Extract capture set from closure bodies (locals referenced but not declared inside closure scope).
	- Classify risky types and emit actionable boundary messages.
**/
class SendSyncAnalyzer {
	static final THREAD_BOUNDARIES:Array<ThreadBoundarySpec> = [
		{
			ownerPath: "sys.thread.Thread",
			method: "create",
			label: "sys.thread.Thread.create(job)"
		},
		{
			ownerPath: "sys.thread.Thread",
			method: "createWithEventLoop",
			label: "sys.thread.Thread.createWithEventLoop(job)"
		},
		{
			ownerPath: "rust.concurrent.Tasks",
			method: "spawn",
			label: "rust.concurrent.Tasks.spawn(job)"
		},
		{
			ownerPath: "rust.async.Tasks",
			method: "spawn",
			label: "rust.async.Tasks.spawn(job)"
		}
	];

	public static function analyze(moduleTypes:Array<ModuleType>, strict:Bool):SendSyncDiagnostics {
		var warnings:Array<SendSyncDiagnostic> = [];
		var errors:Array<SendSyncDiagnostic> = [];
		var seen = new Map<String, Bool>();

		function add(message:String, pos:haxe.macro.Expr.Position):Void {
			var posInfos = haxe.macro.Context.getPosInfos(pos);
			var key = posInfos.file + ":" + posInfos.min + ":" + posInfos.max + ":" + message;
			if (seen.exists(key))
				return;
			seen.set(key, true);
			var diagnostic:SendSyncDiagnostic = {message: message, pos: pos};
			if (strict)
				errors.push(diagnostic)
			else
				warnings.push(diagnostic);
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

		return {warnings: warnings, errors: errors};
	}

	static function scanClassFieldExprs(fields:Array<ClassField>, add:(String, haxe.macro.Expr.Position) -> Void):Void {
		for (field in fields) {
			var expr = field.expr();
			if (expr == null)
				continue;
			scanExpr(expr, add);
		}
	}

	static function scanExpr(root:TypedExpr, add:(String, haxe.macro.Expr.Position) -> Void):Void {
		function visit(expr:TypedExpr):Void {
			var current = unwrapMetaParen(expr);
			switch (current.expr) {
				case TCall(callTarget, args):
					var boundary = resolveThreadBoundary(callTarget);
					if (boundary != null && args != null && args.length > 0)
						analyzeBoundaryJob(boundary, args[0], add);
				case _:
			}
			TypedExprTools.iter(current, visit);
		}
		visit(root);
	}

	static function resolveThreadBoundary(callTarget:TypedExpr):Null<ThreadBoundarySpec> {
		var current = unwrapMetaParenCast(callTarget);
		return switch (current.expr) {
			case TField(_, FStatic(ownerRef, fieldRef)):
				var ownerPath = classTypePath(ownerRef.get());
				var method = fieldRef.get().name;
				matchBoundary(ownerPath, method);
			case _:
				null;
		}
	}

	static function matchBoundary(ownerPath:String, method:String):Null<ThreadBoundarySpec> {
		for (boundary in THREAD_BOUNDARIES) {
			if (boundary.ownerPath == ownerPath && boundary.method == method)
				return boundary;
		}
		return null;
	}

	static function analyzeBoundaryJob(boundary:ThreadBoundarySpec, jobExpr:TypedExpr, add:(String, haxe.macro.Expr.Position) -> Void):Void {
		var unwrappedJob = unwrapMetaParenCast(jobExpr);
		switch (unwrappedJob.expr) {
			case TFunction(fn):
				analyzeThreadClosure(boundary, fn, add, unwrappedJob.pos);
			case _:
				// Non-inline job values can still fail Send/Sync checks in Rust, but their capture set is
				// not recoverable at this callsite without whole-program closure binding analysis.
		}
	}

	static function analyzeThreadClosure(boundary:ThreadBoundarySpec, fn:TFunc, add:(String, haxe.macro.Expr.Position) -> Void,
			fallbackPos:haxe.macro.Expr.Position):Void {
		var declaredIds = collectDeclaredLocalIds(fn);
		var captures = collectCapturedLocals(fn.expr, declaredIds);

		for (capture in captures) {
			var reason = classifyNonSendReason(capture.variable.t);
			if (reason == null)
				continue;
			var localName = capture.variable.name;
			if (localName == null || localName.length == 0)
				localName = "local#" + capture.variable.id;
			var message = boundary.label
				+ " captures `"
				+ localName
				+ "` with "
				+ reason
				+ ". Move owned data into the closure boundary before spawning.";
			add(message, capture.firstUsePos != null ? capture.firstUsePos : fallbackPos);
		}

		var returnReason = classifyNonSendReason(fn.t);
		if (returnReason != null) {
			var message = boundary.label + " returns " + returnReason + ". Spawned jobs should return owned, Send-safe values.";
			add(message, fallbackPos);
		}
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
						if (catches != null) {
							for (capture in catches) {
								if (capture != null && capture.v != null)
									declared.set(capture.v.id, true);
								if (capture != null && capture.expr != null)
									visit(capture.expr);
							}
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

	static function collectCapturedLocals(root:TypedExpr, declaredIds:Map<Int, Bool>):Array<CapturedLocalHit> {
		var byId = new Map<Int, CapturedLocalHit>();

		function visit(expr:TypedExpr):Void {
			var current = unwrapMetaParen(expr);
			switch (current.expr) {
				case TLocal(variable):
					{
						if (variable != null && !declaredIds.exists(variable.id) && !byId.exists(variable.id))
							byId.set(variable.id, {variable: variable, firstUsePos: current.pos});
					}
				case _:
			}
			TypedExprTools.iter(current, visit);
		}

		visit(root);

		var out:Array<CapturedLocalHit> = [];
		for (hit in byId)
			out.push(hit);
		out.sort((a, b) -> compareCaptureHits(a, b));
		return out;
	}

	static function compareCaptureHits(a:CapturedLocalHit, b:CapturedLocalHit):Int {
		var aName = a.variable.name == null ? "" : a.variable.name;
		var bName = b.variable.name == null ? "" : b.variable.name;
		if (aName != bName)
			return aName < bName ? -1 : 1;
		return a.variable.id < b.variable.id ? -1 : (a.variable.id > b.variable.id ? 1 : 0);
	}

	static function classifyNonSendReason(t:Type):Null<String> {
		return classifyNonSendReasonRecursive(t, 0);
	}

	static function classifyNonSendReasonRecursive(t:Type, depth:Int):Null<String> {
		if (t == null || depth > 16)
			return null;

		return switch (t) {
			case TMono(monoRef):
				var resolved = monoRef.get();
				if (resolved == null) "an unresolved monomorph type (cannot be proven Send/Sync)" else classifyNonSendReasonRecursive(resolved, depth + 1);
			case TLazy(loader):
				classifyNonSendReasonRecursive(loader(), depth + 1);
			case TType(_, _):
				classifyNonSendReasonRecursive(TypeTools.follow(t), depth + 1);
			case TAbstract(absRef, params):
				var abs = absRef.get();
				var path = modulePath(abs.pack, abs.name);
				switch (path) {
					case "rust.Ref":
						"borrowed type `rust.Ref<T>`";
					case "rust.MutRef":
						"borrowed type `rust.MutRef<T>`";
					case "rust.Slice":
						"borrowed type `rust.Slice<T>`";
					case "rust.MutSlice":
						"borrowed type `rust.MutSlice<T>`";
					case "Null":
						if (params != null && params.length == 1) classifyNonSendReasonRecursive(params[0], depth + 1) else null;
					case dynamicPath if (dynamicPath == DynamicBoundary.typeName()):
						"dynamic type `" + DynamicBoundary.typeName() + "` (cannot be statically proven Send/Sync)";
					case _:
						null;
				}
			case TDynamic(_):
				"dynamic type `" + DynamicBoundary.typeName() + "` (cannot be statically proven Send/Sync)";
			case _:
				null;
		}
	}

	static inline function classTypePath(classType:ClassType):String {
		return modulePath(classType.pack, classType.name);
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
}

private typedef ThreadBoundarySpec = {
	var ownerPath:String;
	var method:String;
	var label:String;
};

private typedef CapturedLocalHit = {
	var variable:TVar;
	var firstUsePos:haxe.macro.Expr.Position;
};

typedef SendSyncDiagnostic = {
	var message:String;
	var pos:haxe.macro.Expr.Position;
};

typedef SendSyncDiagnostics = {
	var warnings:Array<SendSyncDiagnostic>;
	var errors:Array<SendSyncDiagnostic>;
};
