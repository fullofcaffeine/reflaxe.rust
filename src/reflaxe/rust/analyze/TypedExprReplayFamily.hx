package reflaxe.rust.analyze;

import haxe.macro.Type.ClassField;
import haxe.macro.Type.ClassType;

/**
	Names one source definition that Rust lowering is allowed to emit more than once.

	Why / What / How
	- Haxe stores a default value or constructor body once, but generated Rust may place it at several
	  call, read, or derived-constructor sites. The source byte range identifies the expression, not why
	  those copies belong together.
	- The factories below are the complete admitted set: constructor body, method default, constructor
	  default, and read-only static value. Callers cannot invent an arbitrary family string.
	- Both early analysis and Rust construction build this small immutable value from the declaration
	  owner. Its `id` contains only Haxe module/type/field identities and never a machine-local path.
**/
class TypedExprReplayFamily {
	public final id:String;

	private function new(id:String) {
		if (id == null || id.length == 0 || id.indexOf("\u0000") >= 0)
			throw "Repeated source definitions require a safe stable identity";
		this.id = id;
	}

	/** Identifies copies of one class constructor body, including copies inside derived constructors. */
	public static function constructorBody(owner:ClassType):TypedExprReplayFamily {
		requireConstructor(owner, "constructor-body");
		return new TypedExprReplayFamily("constructor-body:" + ownerIdentity(owner));
	}

	/** Identifies one method default expression inserted at omitted-argument call sites. */
	public static function methodDefault(owner:ClassType, field:ClassField, index:Int):TypedExprReplayFamily {
		requireOwner(owner, "method-default");
		if (field == null || index < 0)
			throw "Method-default replay identities require a method and non-negative argument index";
		switch (field.kind) {
			case FMethod(_):
			case _:
				throw "Method-default replay identities require a method declaration";
		}
		return new TypedExprReplayFamily("method-default:" + ownerIdentity(owner) + ":" + field.name + ":" + index);
	}

	/** Identifies one constructor default expression inserted at omitted-argument construction sites. */
	public static function constructorDefault(owner:ClassType, index:Int):TypedExprReplayFamily {
		requireConstructor(owner, "constructor-default");
		if (index < 0)
			throw "Constructor-default replay identities require a non-negative argument index";
		return new TypedExprReplayFamily("constructor-default:" + ownerIdentity(owner) + ":" + index);
	}

	/** Identifies one read-only static initializer inserted directly at each generated read site. */
	public static function staticReadOnly(owner:ClassType, field:ClassField):TypedExprReplayFamily {
		requireOwner(owner, "read-only-static");
		if (field == null)
			throw "Read-only-static replay identities require a field declaration";
		var readOnly = field.isFinal;
		switch (field.kind) {
			case FVar(_, AccNever):
				readOnly = true;
			case FVar(_, _):
			case _:
				throw "Read-only-static replay identities require a variable declaration";
		}
		if (!readOnly)
			throw "Read-only-static replay identities require a final or non-writable field";
		return new TypedExprReplayFamily("read-only-static:" + ownerIdentity(owner) + ":" + field.name);
	}

	static function requireConstructor(owner:ClassType, label:String):Void {
		requireOwner(owner, label);
		if (owner.constructor == null || owner.constructor.get() == null)
			throw label + " replay identities require a declared constructor";
	}

	static function requireOwner(owner:ClassType, label:String):Void {
		if (owner == null || owner.name == null || owner.name.length == 0)
			throw label + " replay identities require a declared owner type";
	}

	static function ownerIdentity(owner:ClassType):String {
		var parts = owner.pack == null ? [] : owner.pack.copy();
		parts.push(owner.name);
		var typePath = parts.join(".");
		var modulePath = owner.module == null || owner.module.length == 0 ? typePath : owner.module;
		return modulePath + "#" + typePath;
	}
}
