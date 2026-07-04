class Main {
	static function main():Void {
		var text = "metal lifetime island";
		var first = LifetimeIsland.firstWord(text);
		var ok = LifetimeIsland.allWordsAtLeast(text, 5);
		if (first == "metal" && ok) {}
	}
}
