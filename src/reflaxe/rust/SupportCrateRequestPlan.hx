package reflaxe.rust;

#if macro
import haxe.macro.Expr.Position;

/** The only unsafe-code policies admitted by `@:rustSupportCrate`. */
enum abstract SupportCrateUnsafePolicy(String) to String {
	var Forbid = "forbid";
	var Audited = "audited";
}

/** One exact default-registry dependency requested by a support crate. */
final class SupportCrateRegistryDependency {
	public final name:String;
	public final version:String;
	public final defaultFeatures:Bool;
	final featureValues:Array<String>;

	public function new(name:String, version:String, defaultFeatures:Bool, features:Array<String>) {
		this.name = name;
		this.version = version;
		this.defaultFeatures = defaultFeatures;
		this.featureValues = features.copy();
	}

	public function features():Array<String> {
		return featureValues.copy();
	}

	public function equals(other:SupportCrateRegistryDependency):Bool {
		if (other == null || name != other.name || version != other.version || defaultFeatures != other.defaultFeatures)
			return false;
		var otherFeatures = other.features();
		if (featureValues.length != otherFeatures.length)
			return false;
		for (index in 0...featureValues.length) {
			if (featureValues[index] != otherFeatures[index])
				return false;
		}
		return true;
	}
}

/** Stable source owner for one typed support-crate declaration. */
final class SupportCrateDeclarationOwner {
	public final declaration:String;
	public final pos:Position;

	public function new(declaration:String, pos:Position) {
		this.declaration = declaration;
		this.pos = pos;
	}
}

/**
	Pure declaration intent for one support crate.

	Why
	- Typed metadata must be validated and merged before any native source-admission code can run.
	- This type must not be confused with a future plan that owns admitted source bytes.

	What
	- Stores normalized metadata facts and every exact Haxe declaration owner.
	- Contains no resolved filesystem path, source byte, hash, Cargo output, or generated destination.

	How
	- The planner creates fresh arrays and this class keeps private copies.
	- Accessors return copies so later compiler phases cannot mutate request authority.
**/
final class SupportCrateRequest {
	public final name:String;
	public final sourceRoot:String;
	public final unsafePolicy:SupportCrateUnsafePolicy;
	final sourceRootSegmentValues:Array<String>;
	final targetValues:Array<String>;
	final dependencyValues:Array<SupportCrateRegistryDependency>;
	final ownerValues:Array<SupportCrateDeclarationOwner>;

	public function new(name:String, sourceRootSegments:Array<String>, unsafePolicy:SupportCrateUnsafePolicy, targets:Array<String>,
		dependencies:Array<SupportCrateRegistryDependency>, owners:Array<SupportCrateDeclarationOwner>) {
		this.name = name;
		this.sourceRootSegmentValues = sourceRootSegments.copy();
		this.sourceRoot = sourceRootSegmentValues.join("/");
		this.unsafePolicy = unsafePolicy;
		this.targetValues = targets.copy();
		this.dependencyValues = dependencies.copy();
		this.ownerValues = owners.copy();
	}

	public function sourceRootSegments():Array<String> {
		return sourceRootSegmentValues.copy();
	}

	public function targets():Array<String> {
		return targetValues.copy();
	}

	public function dependencies():Array<SupportCrateRegistryDependency> {
		return dependencyValues.copy();
	}

	public function owners():Array<SupportCrateDeclarationOwner> {
		return ownerValues.copy();
	}

	public function withOwner(owner:SupportCrateDeclarationOwner):SupportCrateRequest {
		var nextOwners = ownerValues.copy();
		nextOwners.push(owner);
		return new SupportCrateRequest(name, sourceRootSegmentValues, unsafePolicy, targetValues, dependencyValues, nextOwners);
	}

	public function hasSameDeclaration(other:SupportCrateRequest):Bool {
		if (other == null || name != other.name || sourceRoot != other.sourceRoot || unsafePolicy != other.unsafePolicy)
			return false;
		var otherTargets = other.targets();
		if (!sameStrings(targetValues, otherTargets))
			return false;
		var otherDependencies = other.dependencies();
		if (dependencyValues.length != otherDependencies.length)
			return false;
		for (index in 0...dependencyValues.length) {
			if (!dependencyValues[index].equals(otherDependencies[index]))
				return false;
		}
		return true;
	}

	static function sameStrings(left:Array<String>, right:Array<String>):Bool {
		if (left.length != right.length)
			return false;
		for (index in 0...left.length) {
			if (left[index] != right[index])
				return false;
		}
		return true;
	}
}

/**
	Request-local immutable result of Stage 2A support-crate parsing.

	The compiler resets this plan before each request. Stage 2A deliberately
	contains declaration intent only; Stage 2B will replace the unavailable
	diagnostic with a separate source-admission plan that owns exact bytes.
**/
final class SupportCrateRequestPlan {
	final requestValues:Array<SupportCrateRequest>;

	public function new(requests:Array<SupportCrateRequest>) {
		this.requestValues = requests.copy();
	}

	public static function empty():SupportCrateRequestPlan {
		return new SupportCrateRequestPlan([]);
	}

	public function isEmpty():Bool {
		return requestValues.length == 0;
	}

	public function requests():Array<SupportCrateRequest> {
		return requestValues.copy();
	}

	public function firstOwner():Null<SupportCrateDeclarationOwner> {
		if (requestValues.length == 0)
			return null;
		var owners = requestValues[0].owners();
		return owners.length == 0 ? null : owners[0];
	}
}
#end
