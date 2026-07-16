import reflaxe.rust.ast.RustAST.RustConstArgument;
import reflaxe.rust.ast.RustAST.RustGenericArgument;
import reflaxe.rust.ast.RustAST.RustGenericBound;
import reflaxe.rust.ast.RustAST.RustGenericParameters;
import reflaxe.rust.ast.RustAST.RustIdentifier;
import reflaxe.rust.ast.RustAST.RustLifetime;
import reflaxe.rust.ast.RustAST.RustPath;
import reflaxe.rust.ast.RustAST.RustPathSegment;
import reflaxe.rust.ast.RustAST.RustPattern;
import reflaxe.rust.ast.RustAST.RustType;
import reflaxe.rust.ast.RustPathAnalysis;

class RustStructuralPathAnalysisContract {
	static function expect(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function path(names:Array<String>):RustPath {
		return RustPath.relative([for (name in names) RustPathSegment.plain(name)]);
	}

	static function named(name:String):RustType {
		return RNamed(RustPath.single(name));
	}

	static function increment(counts:Map<String, Int>, name:Null<String>):Void {
		if (name == null)
			return;
		counts.set(name, (counts.exists(name) ? counts.get(name) : 0) + 1);
	}

	static function count(counts:Map<String, Int>, name:String):Int {
		return counts.exists(name) ? counts.get(name) : 0;
	}

	static function incrementFirstPathIdentifier(counts:Map<String, Int>, candidate:RustPath):Void {
		if (candidate.segmentCount > 0)
			increment(counts, candidate.segmentAt(0).identifier.name);
	}

	static function main():Void {
		var local = RustPath.single("value");
		expect(RustPathAnalysis.localIdentifierName(local) == "value",
			"one argument-free relative segment must retain local identity");
		expect(RustPathAnalysis.localIdentifierName(path(["module", "value"])) == null,
			"qualified target paths must not be mistaken for locals");
		expect(RustPathAnalysis.localIdentifierName(RustPath.cratePath([RustPathSegment.plain("value")])) == null,
			"rooted target paths must not be mistaken for locals");
		expect(RustPathAnalysis.localIdentifierName(RustPath.relative([
			RustPathSegment.angle("value", [GenericType(named("T"))])
		])) == null, "generic target paths must not be mistaken for locals");

		var dynamicFrom = path(["hxrt", "dynamic", "from"]);
		expect(RustPathAnalysis.matchesPlainRelative(dynamicFrom, ["hxrt", "dynamic", "from"]),
			"the exact compiler-owned target path must match structurally");
		expect(!RustPathAnalysis.matchesPlainRelative(path(["hxrtual", "dynamic", "from"]), ["hxrt", "dynamic", "from"]),
			"identifier prefixes must not satisfy exact target-path matching");
		expect(!RustPathAnalysis.matchesPlainRelative(path(["hxrt", "dynamic", "from", "extra"]), ["hxrt", "dynamic", "from"]),
			"target-path matching must reject descendants");
		expect(!RustPathAnalysis.matchesPlainRelative(RustPath.absolute([
			RustPathSegment.plain("hxrt"),
			RustPathSegment.plain("dynamic"),
			RustPathSegment.plain("from")
		]), ["hxrt", "dynamic", "from"]), "target-path matching must preserve root identity");
		expect(!RustPathAnalysis.matchesPlainRelative(RustPath.relative([
			RustPathSegment.plain("hxrt"),
			RustPathSegment.plain("dynamic"),
			RustPathSegment.angle("from", [GenericType(named("T"))])
		]), ["hxrt", "dynamic", "from"]), "generic segments must not masquerade as plain target paths");
		var nativeSocket = RustPath.cratePath([
			RustPathSegment.plain("native_socket_addr_tools"),
			RustPathSegment.plain("SocketAddr")
		]);
		expect(RustPathAnalysis.matchesPlainCrate(nativeSocket, ["native_socket_addr_tools", "SocketAddr"]),
			"crate-rooted compiler targets must match through the shared structural authority");
		expect(!RustPathAnalysis.matchesPlainCrate(path(["native_socket_addr_tools", "SocketAddr"]),
			["native_socket_addr_tools", "SocketAddr"]), "crate matching must preserve root identity");

		expect(RustPathAnalysis.belongsToNamespace(path(["hxrt", "dynamic"]), "hxrt"),
			"an exact leading plain segment must own its namespace");
		expect(RustPathAnalysis.belongsToNamespace(RustPath.cratePath([
			RustPathSegment.plain("hxrt"),
			RustPathSegment.plain("dynamic")
		]), "hxrt"), "namespace ownership must remain visible under an explicit root");
		expect(!RustPathAnalysis.belongsToNamespace(path(["hxrtual", "dynamic"]), "hxrt"),
			"namespace ownership must reject prefix collisions");
		expect(!RustPathAnalysis.belongsToNamespace(path(["other", "hxrt"]), "hxrt"),
			"a later segment must not become the path namespace");
		expect(!RustPathAnalysis.belongsToNamespace(RustPath.relative([
			RustPathSegment.angle("hxrt", [GenericType(named("T"))])
		]), "hxrt"), "a generic identifier is not a namespace segment");

		var lifetime = RustLifetime.named("a");
		var hxrtPayload = RustPath.relative([
			RustPathSegment.plain("hxrt"),
			RustPathSegment.plain("dynamic"),
			RustPathSegment.angle("DynamicBox", [
				GenericLifetime(lifetime),
				GenericType(named("Payload")),
				GenericConst(RustConstArgument.path(path(["limits", "N"])))
			])
		]);
		var qualified = RustPath.qualified(RNamed(RustPath.relative([
			RustPathSegment.angle("Outer", [GenericType(RNamed(hxrtPayload))])
		])), RustPath.relative([
			RustPathSegment.angle("Factory", [
				GenericLifetime(lifetime),
				GenericConst(RustConstArgument.path(path(["limits", "N"])))
			])
		]), [
			RustPathSegment.parenthesized("make", [named("Input")], named("Output"))
		]);

		var visited:Map<String, Int> = [];
		RustPathAnalysis.visitPathTree(qualified, candidate -> incrementFirstPathIdentifier(visited, candidate));
		expect(count(visited, "make") == 1, "the associated-item path must be visited");
		expect(count(visited, "Outer") == 1, "the qualified self type must be visited");
		expect(count(visited, "hxrt") == 1, "nested generic type paths must be visited once");
		expect(count(visited, "Payload") == 1, "nested type arguments must be visited");
		expect(count(visited, "limits") == 2, "const paths in self and trait generics must be visited");
		expect(count(visited, "Factory") == 1, "the qualified trait path must be visited");
		expect(count(visited, "Input") == 1 && count(visited, "Output") == 1,
			"parenthesized trait inputs and outputs must be visited");

		var patternPaths:Map<String, Int> = [];
		RustPathAnalysis.visitPatternTree(PAlias("whole", POr([
			PWildcard,
			PTupleStruct(path(["Envelope"]), [
				PAlias("payload", PPath(hxrtPayload))
			])
		])), candidate -> incrementFirstPathIdentifier(patternPaths, candidate));
		expect(count(patternPaths, "Envelope") == 1,
			"tuple-struct paths nested below alias/or patterns must be visited");
		expect(count(patternPaths, "hxrt") == 1 && count(patternPaths, "Payload") == 1,
			"alias-pattern traversal must expose paths and their nested generic arguments");

		var parameters = RustGenericParameters.of([
			GenericLifetimeParam(RustIdentifier.named("a"), []),
			GenericTypeParam(RustIdentifier.named("T"), [
				GenericTraitBound(RustPath.relative([
					RustPathSegment.angle("Bound", [GenericType(RNamed(hxrtPayload))])
				]))
			], named("DefaultValue")),
			GenericConstParam(RustIdentifier.named("N"), named("usize"),
				RustConstArgument.path(path(["hxrt", "limits", "DEFAULT_N"])))
		]);
		var parameterPaths:Map<String, Int> = [];
		RustPathAnalysis.visitGenericParameters(parameters, candidate -> incrementFirstPathIdentifier(parameterPaths, candidate));
		expect(count(parameterPaths, "Bound") == 1, "generic trait bounds must be visited");
		expect(count(parameterPaths, "hxrt") == 2, "nested type and const defaults must expose exact runtime namespaces");
		expect(count(parameterPaths, "Payload") == 1 && count(parameterPaths, "limits") == 1,
			"nested generic type and const paths must remain structurally visible");
		expect(count(parameterPaths, "DefaultValue") == 1 && count(parameterPaths, "usize") == 1,
			"generic defaults and const parameter types must be visited");

		Sys.println("structural-path-analysis-ok");
	}
}
