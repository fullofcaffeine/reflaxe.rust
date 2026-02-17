package rust.fs;

/**
	`rust.fs.NativeFile` (internal std binding)

	Why
	- `sys.io.FileInput` / `sys.io.FileOutput` need to keep an OS file handle open across calls.
	- Storing a Rust file handle inside an untyped runtime box is not viable because that box requires
	  `Clone`, and `std::fs::File` is not `Clone`.
	- The Rust target already uses `rust.HxRef<T>` (`Rc<RefCell<T>>`) for shared, cloneable handles.

	What
	- A typing-only handle for Rust's `std::fs::File`.
	- This is not meant to be used directly by applications; it exists so std overrides can keep
	  file handles in `HxRef<...>` fields without exposing `__rust__` to app code.

	How
	- `@:native("std::fs::File")` maps this extern class to the Rust type path.
	- `sys.io.FileInput` / `sys.io.FileOutput` store `Null<HxRef<NativeFile>>` so `close()` can drop
	  the handle (set it to `null`), releasing the OS resource.
**/
@:native("std::fs::File")
extern class NativeFile {}
