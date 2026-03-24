import haxe.json.Value;

class Main {
	static function findField(fields:Array<{name:String, value:Value}>, name:String):Value {
		for (entry in fields) {
			if (entry.name == name)
				return entry.value;
		}
		throw "missing field: " + name;
	}

	static function objectFields(value:Value):Array<{name:String, value:Value}> {
		return switch (value) {
			case JObject(keys, values):
				var out:Array<{name:String, value:Value}> = [];
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

	static function renderValue(value:Value):String {
		return switch (value) {
			case JNull:
				"null";
			case JBool(v):
				"bool:" + Std.string(v);
			case JNumber(v):
				"number:" + Std.string(v);
			case JString(v):
				"string:" + v;
			case JArray(items):
				"array:" + [for (item in items) renderValue(item)].join("|");
			case JObject(keys, values):
				var pairs:Array<String> = [];
				var i = 0;
				while (i < keys.length) {
					pairs.push(keys[i] + "=" + renderValue(values[i]));
					i = i + 1;
				}
				"object:" + pairs.join(",");
		}
	}

	static function main() {
		var parsed = haxe.Json.parseValue('{"name":"Ada","score":4.5,"flags":[true,false],"meta":{"ok":true},"empty":null}');
		var fields = objectFields(parsed);
		Sys.println("name=" + renderValue(findField(fields, "name")));
		Sys.println("score=" + renderValue(findField(fields, "score")));
		Sys.println("flags=" + renderValue(findField(fields, "flags")));
		Sys.println("meta=" + renderValue(findField(fields, "meta")));
		Sys.println("empty=" + renderValue(findField(fields, "empty")));

		var dyn:Dynamic = haxe.Json.parse('{"n":3,"label":"ok"}');
		Reflect.setField(dyn, "n", 4);
		var extra:Array<Dynamic> = [];
		extra.push(1);
		extra.push(2);
		Reflect.setField(dyn, "extra", extra);
		var pretty = haxe.Json.stringify(dyn, null, "  ").split("\n").join("\\n");
		Sys.println("pretty=" + pretty);
	}
}
