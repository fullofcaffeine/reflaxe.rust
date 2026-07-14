import sample.Primary;
import sample.Primary.Flavor;
import sample.Primary.Secondary;

class Main {
	static var lookupCalls = 0;

	static function classLookup():String {
		lookupCalls++;
		return "sample.Secondary";
	}

	static function enumLookup():String {
		lookupCalls++;
		return "sample.Flavor";
	}

	static function main():Void {
		Sys.println(Type.getClassName(Primary));
		Sys.println(Type.getClassName(Secondary));
		Sys.println(Type.getEnumName(Flavor));

		var resolvedClass = Type.resolveClass(classLookup());
		Sys.println(resolvedClass == Secondary);
		Sys.println(Type.getClassName(resolvedClass));
		Sys.println(Type.resolveClass("sample.Missing") == null);
		Sys.println(Type.resolveClass("sample.Primary.Secondary") == null);

		var resolvedEnum = Type.resolveEnum(enumLookup());
		Sys.println(resolvedEnum == Flavor);
		Sys.println(Type.getEnumName(resolvedEnum));
		Sys.println(Type.resolveEnum("sample.Missing") == null);
		Sys.println(Type.resolveEnum("sample.Primary.Flavor") == null);
		Sys.println(Type.getEnumConstructs(resolvedEnum).join(","));
		Sys.println(Type.getEnumConstructs(Flavor).join(","));
		Sys.println("lookupCalls=" + lookupCalls);
	}
}
