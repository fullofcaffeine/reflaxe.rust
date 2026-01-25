abstract Meters(Int) from Int to Int {
	public inline function new(v: Int) this = v;

	@:from public static inline function fromFloat(v: Float): Meters {
		return new Meters(cast v);
	}

	public inline function add(other: Meters): Meters {
		return new Meters(this + other);
	}
}
