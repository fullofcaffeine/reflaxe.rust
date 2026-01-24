package rust;

/**
 * rust.HxRef<T>
 *
 * A typing-only representation of the runtime `HxRef<T>` (currently `Rc<RefCell<T>>`)
 * used by reflaxe.rust for Haxe class instances in portable mode.
 *
 * This exists so framework helpers (e.g. serde wrappers) can express `HxRef<T>` in
 * their signatures without leaking raw `__rust__` into application code.
 */
@:coreType
extern abstract HxRef<T> {
	@:from public static inline function fromValue<T>(v: T): HxRef<T> {
		return cast v;
	}
}

