package haxe.json;

/**
	Typed JSON value tree for `reflaxe.rust`.

	Why
	- `haxe.Json.parse` must keep the upstream untyped return contract for stdlib compatibility.
	- Application/example code should still be able to decode JSON without propagating untyped values.

	What
	- A closed enum that models JSON values:
	  - `JNull`
	  - `JBool`
	  - `JNumber`
	  - `JString`
	  - `JObject` (`keys:Array<String>`, `values:Array<Value>`)
	  - `JArray` (`Array<Value>`)

	How
	- `haxe.Json.parseValue(...)` converts the dynamic runtime representation into this enum.
	- Callers can then pattern-match on `Value` and stay fully typed after the JSON boundary.
**/
enum Value {
	JNull;
	JBool(value:Bool);
	JNumber(value:Float);
	JString(value:String);
	JObject(keys:Array<String>, values:Array<Value>);
	JArray(items:Array<Value>);
}
