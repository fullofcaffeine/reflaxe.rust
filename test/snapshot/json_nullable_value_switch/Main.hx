import haxe.json.Value;

typedef JsonField = {
	final name:String;
	final value:Value;
}

class Main {
	static function objectFields(value:Value):Array<JsonField> {
		return switch (value) {
			case JObject(keys, values):
				var out:Array<JsonField> = [];
				var i = 0;
				while (i < keys.length) {
					out.push({name: keys[i], value: values[i]});
					i = i + 1;
				}
				out;
			case _:
				throw "expected object";
		}
	}

	static function readOptionalField(fields:Array<JsonField>, name:String):Null<Value> {
		for (field in fields) {
			if (field.name == name) {
				return field.value;
			}
		}
		return null;
	}

	static function describeOptionalField(fields:Array<JsonField>, name:String):String {
		return switch (readOptionalField(fields, name)) {
			case null:
				"missing";
			case JNull:
				"json-null";
			case JString(value):
				"string:" + value;
			case JNumber(value):
				"number:" + Std.string(value);
			case JBool(value):
				"bool:" + Std.string(value);
			case _:
				"other";
		}
	}

	static function main():Void {
		final fields = objectFields(haxe.Json.parseValue('{"name":"Ada","score":4.5,"enabled":true,"tags":["haxe"],"empty":null}'));
		Sys.println("name=" + describeOptionalField(fields, "name"));
		Sys.println("score=" + describeOptionalField(fields, "score"));
		Sys.println("enabled=" + describeOptionalField(fields, "enabled"));
		Sys.println("tags=" + describeOptionalField(fields, "tags"));
		Sys.println("empty=" + describeOptionalField(fields, "empty"));
		Sys.println("missing=" + describeOptionalField(fields, "missing"));
	}
}
