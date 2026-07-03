@:rustGeneric("T: std::fmt::Display + Clone + Send + Sync")
@:rustImpl("std::fmt::Display", "fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result { write!(f, \"BoundedBox({})\", self.value) }")
class BoundedBox<T> {
	public var value:T;

	public function new(value:T) {
		this.value = value;
	}

	public function cloneValue():T {
		return value;
	}
}

class Main {
	static function main():Void {
		var boxed = new BoundedBox("metal");
		Sys.println(BoundTools.describe(boxed.cloneValue()));
	}
}
