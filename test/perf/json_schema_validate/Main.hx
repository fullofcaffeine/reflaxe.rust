import haxe.json.Value;

typedef NestedPayload = {
	var count:Int;
	var tag:String;
}

typedef ValidatedPayload = {
	var id:Int;
	var label:String;
	var active:Bool;
	var flags:Array<Bool>;
	var weights:Array<Float>;
	var nested:NestedPayload;
	var emptyWasNull:Bool;
}

class Main {
	static inline final OUTER_RUNS = 18;
	static inline final INNER_RUNS = 40;

	static function main() {
		var acc = crunch();
		if (acc == -1) {
			Sys.println("unreachable");
		}
	}

	static function crunch():Int {
		var acc = 0;
		var run = 0;
		while (run < OUTER_RUNS) {
			var inner = 0;
			while (inner < INNER_RUNS) {
				var parsed = haxe.Json.parseValue(buildJson(run, inner, acc));
				var payload = validatePayload(parsed);
				acc = foldPayload(acc, payload);
				inner = inner + 1;
			}
			run = run + 1;
		}
		return acc;
	}

	static function buildJson(run:Int, inner:Int, acc:Int):String {
		var id = run * INNER_RUNS + inner;
		var label = "schema-" + Std.string(run) + "-" + Std.string(inner);
		var active = inner % 2 == 0;
		var flagA = inner % 2 == 0;
		var flagB = inner % 3 == 0;
		var flagC = inner % 5 == 0;
		var weightA = id % 17;
		var weightB = (acc + inner) % 23;
		var weightC = (run + inner) % 29;
		var count = acc + inner;
		var tag = "tag-" + Std.string(run & 7);
		return '{"id":' + Std.string(id)
			+ ',"label":"' + label + '"'
			+ ',"active":' + boolJson(active)
			+ ',"flags":[' + boolJson(flagA) + "," + boolJson(flagB) + "," + boolJson(flagC) + "]"
			+ ',"weights":[' + Std.string(weightA) + "," + Std.string(weightB) + "," + Std.string(weightC) + "]"
			+ ',"nested":{"count":' + Std.string(count) + ',"tag":"' + tag + '"}'
			+ ',"empty":null}';
	}

	static function boolJson(value:Bool):String {
		return value ? "true" : "false";
	}

	static function validatePayload(value:Value):ValidatedPayload {
		return {
			id: expectInt(objectField(value, "id")),
			label: expectString(objectField(value, "label")),
			active: expectBool(objectField(value, "active")),
			flags: expectBoolArray(objectField(value, "flags")),
			weights: expectNumberArray(objectField(value, "weights")),
			nested: validateNested(objectField(value, "nested")),
			emptyWasNull: expectNull(objectField(value, "empty"))
		};
	}

	static function validateNested(value:Value):NestedPayload {
		return {
			count: expectInt(objectField(value, "count")),
			tag: expectString(objectField(value, "tag"))
		};
	}

	static function foldPayload(acc:Int, payload:ValidatedPayload):Int {
		var next = (acc + payload.id + payload.label.length + payload.nested.count + payload.nested.tag.length) & 0x7FFFFFFF;
		next = (next + (payload.active ? 17 : 3)) & 0x7FFFFFFF;
		for (flag in payload.flags) {
			next = (next ^ (flag ? 0x55 : 0x33)) & 0x7FFFFFFF;
		}
		for (weight in payload.weights) {
			next = (next + Std.int(weight * 3)) & 0x7FFFFFFF;
		}
		if (payload.emptyWasNull) {
			next = (next + 7) & 0x7FFFFFFF;
		}
		return next;
	}

	static function objectField(value:Value, name:String):Value {
		return switch (value) {
			case JObject(keys, values):
				var i = 0;
				while (i < keys.length) {
					if (keys[i] == name) {
						return values[i];
					}
					i = i + 1;
				}
				throw "missing field: " + name;
			case _:
				throw "expected object field: " + name;
		}
	}

	static function expectBoolArray(value:Value):Array<Bool> {
		return switch (value) {
			case JArray(items):
				var out:Array<Bool> = [];
				for (item in items) {
					out.push(expectBool(item));
				}
				out;
			case _:
				throw "expected bool array";
		}
	}

	static function expectNumberArray(value:Value):Array<Float> {
		return switch (value) {
			case JArray(items):
				var out:Array<Float> = [];
				for (item in items) {
					out.push(expectNumber(item));
				}
				out;
			case _:
				throw "expected number array";
		}
	}

	static function expectBool(value:Value):Bool {
		return switch (value) {
			case JBool(v):
				v;
			case _:
				throw "expected bool";
		}
	}

	static function expectInt(value:Value):Int {
		return Std.int(expectNumber(value));
	}

	static function expectNumber(value:Value):Float {
		return switch (value) {
			case JNumber(v):
				v;
			case _:
				throw "expected number";
		}
	}

	static function expectString(value:Value):String {
		return switch (value) {
			case JString(v):
				v;
			case _:
				throw "expected string";
		}
	}

	static function expectNull(value:Value):Bool {
		return switch (value) {
			case JNull:
				true;
			case _:
				throw "expected null";
		}
	}
}
