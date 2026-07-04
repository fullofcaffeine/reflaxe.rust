import haxe.json.Value;

enum abstract Mode(String) to String {
	var Run = "run";
	var Stop = "stop";
}

typedef Payload = {
	var enabled:Bool;
	var label:String;
	var mode:Mode;
	var functionNumber:Int;
}

class Binding {
	public final enabled:Bool;
	public final label:String;
	public final mode:Mode;
	public final functionNumber:Int;

	public function new(fields:Payload) {
		this.enabled = fields.enabled;
		this.label = fields.label == null ? "" : fields.label;
		this.mode = fields.mode == null ? Stop : fields.mode;
		this.functionNumber = fields.functionNumber;
	}

	public function summary():String {
		return label + ":" + mode + ":" + functionNumber + ":" + enabled;
	}
}

class Main {
	static function buildNumber(seed:Int):Int {
		return seed * 10 + 2;
	}

	static function buildMode(n:Int):Mode {
		return n > 10 ? Run : Stop;
	}

	static function makePayload(seed:Int):Payload {
		var n = buildNumber(seed);
		return {
			enabled: n > 0,
			label: "fn-" + n,
			mode: buildMode(n),
			functionNumber: n
		};
	}

	static function forward(seed:Int):Payload {
		return makePayload(seed);
	}

	static function describe(p:Payload):String {
		return p.label + ":" + p.mode + ":" + p.functionNumber;
	}

	static function optionalField(object:Value, name:String):Value {
		return switch object {
			case JObject(keys, values):
				var i = 0;
				while (i < keys.length) {
					if (keys[i] == name) {
						return values[i];
					}
					i = i + 1;
				}
				JNull;
			case _:
				throw "expected object";
		}
	}

	static function stringField(object:Value, name:String, fallback:String):String {
		return switch optionalField(object, name) {
			case JString(value): value;
			case JNull: fallback;
			case _: throw "expected string field: " + name;
		}
	}

	static function boolField(object:Value, name:String, fallback:Bool):Bool {
		return switch optionalField(object, name) {
			case JBool(value): value;
			case JNull: fallback;
			case _: throw "expected bool field: " + name;
		}
	}

	static function intField(object:Value, name:String, fallback:Int):Int {
		return switch optionalField(object, name) {
			case JNumber(value): Std.int(value);
			case JNull: fallback;
			case _: throw "expected int field: " + name;
		}
	}

	static function modeField(object:Value, name:String, fallback:Mode):Mode {
		return switch optionalField(object, name) {
			case JString(value): cast value;
			case JNull: fallback;
			case _: throw "expected mode field: " + name;
		}
	}

	static function payloadFromValue(value:Value):Payload {
		return {
			enabled: boolField(value, "enabled", false),
			label: stringField(value, "label", ""),
			mode: modeField(value, "mode", Stop),
			functionNumber: intField(value, "functionNumber", -1)
		};
	}

	static function makeBindingFromPayload():Binding {
		return new Binding(forward(4));
	}

	static function makeBindingFromLiteral():Binding {
		return new Binding({
			enabled: false,
			label: "none",
			mode: Stop,
			functionNumber: -1
		});
	}

	static function makeBindingFromJsonValue():Binding {
		var value = haxe.Json.parseValue('{"enabled":true,"label":"json","mode":"run","functionNumber":12}');
		return new Binding(payloadFromValue(value));
	}

	static function main():Void {
		var p = forward(4);
		Sys.println(p.enabled);
		Sys.println(p.label);
		Sys.println(p.mode);
		Sys.println(p.functionNumber);
		Sys.println(p.functionNumber + 1);
		Sys.println(describe(p));
		Sys.println(makeBindingFromPayload().summary());
		Sys.println(makeBindingFromLiteral().summary());
		Sys.println(makeBindingFromJsonValue().summary());
	}
}
