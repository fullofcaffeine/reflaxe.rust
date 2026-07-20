class CrossModuleBoundary {
	public static final repeated:Dynamic = 213213;
	public var value:Dynamic;

	public function new(value:Dynamic = 212212) {
		this.value = value;
	}

	public static function consume(value:Dynamic = 211211):Void {
		if (value == null) {}
	}
}
