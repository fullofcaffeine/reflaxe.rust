typedef Fields = {
	var ?label:String;
}

class Holder {
	final fields:Fields;

	public function new(fields:Fields) {
		this.fields = fields;
	}

	public function label():String {
		return fields.label;
	}
}

class Main {
	static function main():Void {
		Sys.println(new Holder({}).label() == null);
		Sys.println(new Holder({label: "ready"}).label());
	}
}
