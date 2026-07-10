package rust;

/**
 * `rust.HxRef<T>` is the opaque shared handle used where a typed public facade must expose Haxe
 * reference semantics.
 *
 * Why
 * - Concurrency, async, and framework bridges need to pass class/resource handles without raw Rust
 *   snippets or `Dynamic`.
 * - Those public signatures require a stable Haxe-level name even though the backend must remain
 *   free to improve its ownership and synchronization strategy.
 *
 * What
 * - A typing-only, qualified public handle carrying shared/null-capable Haxe-reference semantics.
 * - It is not a promise that the generated Rust representation is `Arc`, `HxCell`, `RwLock`, or
 *   any other particular type or layout.
 *
 * How
 * - The compiler lowers `HxRef<T>` to the active runtime/reference representation.
 * - `@:from` permits typed facade values to cross the Haxe declaration boundary; callers should
 *   use the owning facade rather than depending on handle internals.
 * - Compatibility protects the Haxe type name, generic shape, and documented facade behavior, not
 *   internal methods, memory layout, synchronization primitive, or generated alias path.
 */
@:coreType
extern abstract HxRef<T> {
	/**
	 * Converts a facade value into its opaque handle type.
	 *
	 * Why: Haxe extern signatures sometimes expose the handle while the typed expression is already
	 * the corresponding reference value.
	 * What: A compile-time typing conversion only.
	 * How: The compiler erases the cast into its selected reference representation; applications
	 * must not treat it as allocation or representation evidence.
	 */
	@:from public static inline function fromValue<T>(v:T):HxRef<T> {
		return cast v;
	}
}
