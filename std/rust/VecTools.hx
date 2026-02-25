package rust;

/**
 * `rust.VecTools`
 *
 * Why
 * - `rust.Vec<T>` helpers are widely used in Rust-first snapshots/examples.
 * - The previous implementation used inline `untyped __rust__` bodies for routine
 *   vec operations (`len`, `get`, `set`, conversion helpers).
 * - Those inline bodies contributed directly to `ERaw` fallback noise in metal diagnostics.
 *
 * What
 * - A typed extern facade backed by a hand-written Rust helper module.
 * - This preserves the existing Haxe API while removing raw injection from this boundary.
 *
 * How
 * - `@:native("crate::vec_tools::VecTools")` binds to the generated Rust module from
 *   `@:rustExtraSrc("rust/native/vec_tools.rs")`.
 * - Borrow-sensitive APIs (`getRef`, `getMut`) remain typed (`Option<Ref<T>>`,
 *   `Option<MutRef<T>>`) so callers keep Rust lifetime constraints visible at compile time.
 * - Callers cross the native boundary through typed signatures only; no `Dynamic` or `Reflect`
 *   fallback is required here.
 */
@:native("crate::vec_tools::VecTools")
@:rustExtraSrc("rust/native/vec_tools.rs")
extern class VecTools {
	@:rustGeneric("T: Clone")
	public static function fromArray<T>(a:Array<T>):Vec<T>;

	@:rustGeneric("T: Clone")
	public static function toArray<T>(v:Vec<T>):Array<T>;

	public static function len<T>(v:Ref<Vec<T>>):Int;

	@:rustGeneric("T: Clone")
	public static function get<T>(v:Ref<Vec<T>>, index:Int):Option<T>;

	/**
	 * Borrow-first element access.
	 *
	 * Why:
	 * - `get(...)` clones because it returns an owned `T`.
	 * - In metal/profile code we often want `Option<&T>` instead.
	 *
	 * How:
	 * - Requires a borrowed `Ref<Vec<T>>` so the returned `Ref<T>` cannot outlive the borrow scope.
	 */
	public static function getRef<T>(v:Ref<Vec<T>>, index:Int):Option<Ref<T>>;

	/**
	 * Mutable element access (`Option<&mut T>`).
	 *
	 * NOTE:
	 * - Requires `MutRef<Vec<T>>` (so the vec binding is borrowed mutably).
	 * - Prefer using this inside `Borrow.withMut(...)` or `MutSliceTools.with(...)`.
	 */
	public static function getMut<T>(v:MutRef<Vec<T>>, index:Int):Option<MutRef<T>>;

	public static function set<T>(v:Vec<T>, index:Int, value:T):Vec<T>;
}
