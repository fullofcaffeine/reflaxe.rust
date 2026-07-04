/**
 * `LifetimeIsland`
 *
 * Why:
 * - Some Rust APIs need lifetimes or higher-ranked closure bounds that Haxe cannot express directly.
 * - Metal code should still call those APIs through typed Haxe surfaces, not app-side `__rust__`
 *   snippets or stringly wrappers.
 *
 * What:
 * - A tiny extern facade over `native/lifetime_island.rs`.
 * - The Rust module owns the lifetime-heavy implementation and returns owned values to Haxe.
 *
 * How:
 * - `@:rustExtraSrc(...)` copies the handwritten Rust module into the generated crate.
 * - `@:native(...)` binds this Haxe type and its methods to the Rust module path.
 */
@:native("crate::lifetime_island::LifetimeIsland")
@:rustExtraSrc("native/lifetime_island.rs")
extern class LifetimeIsland {
	@:native("first_word_owned")
	public static function firstWord(text:String):String;

	@:native("all_words_at_least")
	public static function allWordsAtLeast(text:String, minLen:Int):Bool;
}
