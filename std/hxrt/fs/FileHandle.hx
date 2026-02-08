package hxrt.fs;

/**
	`hxrt.fs.FileHandle` (Rust runtime binding)

	Why
	- `sys.io.FileInput` / `sys.io.FileOutput` must keep a file handle open across calls.
	- We cannot store `std::fs::File` directly in a Haxe `Dynamic` or other boxed value because it is
	  not `Clone`, but Haxe values are generally assumed to be reusable.

	What
	- A typing-only handle for the runtime type `hxrt::fs::FileHandle`.

	How
	- `@:native("hxrt::fs::FileHandle")` maps this extern to the Rust runtime struct.
	- Haxe code stores it behind `rust.HxRef<T>` (runtime `Rc<RefCell<T>>`), which is cloneable.
**/
@:native("hxrt::fs::FileHandle")
extern class FileHandle {}

