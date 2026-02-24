package reflaxe.rust.compiler;

/**
	RustClassContext

	Why
	- Class compilation currently threads context through many function parameters and mutable fields.
	- A typed class-scoped context makes the extraction from monolithic compiler logic explicit and
	  lets analyzers/passes reason about class-level state in one place.

	What
	- Class-level identity for the file currently being lowered.
	- This is intentionally small for now and will be expanded as module extraction continues.

	How
	- Constructed when class compilation begins and discarded when it ends.
	- Stored as a strongly-typed field (`currentClassContext`) rather than ad-hoc tuples/maps.
**/
class RustClassContext {
	public final classKey:String;
	public final moduleName:String;
	public final rustTypeName:String;

	public function new(classKey:String, moduleName:String, rustTypeName:String) {
		this.classKey = classKey;
		this.moduleName = moduleName;
		this.rustTypeName = rustTypeName;
	}
}
