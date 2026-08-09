package reflaxe.rust.analyze;

import haxe.macro.Type.ClassField;
import haxe.macro.Type.ClassType;

/**
	Lists every class field that can own executable typed Haxe code.

	Why / What / How
	- Haxe stores a constructor separately from ordinary instance and static fields. Three early
	  analyzers previously copied their own loops, so some of them silently skipped constructor bodies.
	- This helper returns constructor, instance, and static fields in one deterministic order.
	- Callers still decide what facts to collect from each field; this helper owns only the complete
	  definition of which class slots can contain executable source.
**/
class TypedClassExecutableFields {
	public static function collect(classType:ClassType):Array<ClassField> {
		if (classType == null)
			return [];
		var fields:Array<ClassField> = [];
		if (classType.constructor != null) {
			var constructor = classType.constructor.get();
			if (constructor != null)
				fields.push(constructor);
		}
		var instanceFields = classType.fields.get();
		if (instanceFields != null)
			for (field in instanceFields)
				if (field != null)
					fields.push(field);
		var staticFields = classType.statics.get();
		if (staticFields != null)
			for (field in staticFields)
				if (field != null)
					fields.push(field);
		return fields;
	}
}
