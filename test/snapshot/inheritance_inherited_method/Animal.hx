class Animal {
	public function new() {}

	public function sound():String {
		return "animal";
	}

	public function speak():String {
		return this.sound();
	}
}

