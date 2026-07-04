typedef Payload = {
	var name:String;
	@:optional var nickname:String;
	@:optional var enabled:Bool;
}

class Main {
	static function makeMissing():Payload {
		return {
			name: "Ada"
		};
	}

	static function makePresent():Payload {
		return {
			name: "Grace",
			nickname: "Amazing",
			enabled: true
		};
	}

	static function describe(p:Payload):String {
		var nick = p.nickname == null ? "<missing>" : p.nickname;
		var active = p.enabled == true ? "enabled" : "disabled-or-missing";
		return p.name + ":" + nick + ":" + active;
	}

	static function main():Void {
		var missing = makeMissing();
		Sys.println(missing.name);
		Sys.println(missing.nickname == null);
		Sys.println(missing.enabled == null);
		Sys.println(describe(missing));

		var present = makePresent();
		Sys.println(present.name);
		Sys.println(present.nickname == null);
		Sys.println(present.enabled == null);
		Sys.println(describe(present));
	}
}
