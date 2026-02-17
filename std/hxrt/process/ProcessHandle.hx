package hxrt.process;

/**
	`hxrt.process.ProcessHandle` (Rust runtime binding)

	Why
	- `sys.io.Process` needs to hold a live OS process (`std::process::Child`) plus pipes.
	- `Child` and its stdio handles are not `Clone`, so they cannot be stored inside an untyped box.
	- reflaxe.rust solves this by storing runtime handles behind `rust.HxRef<T>` (`Rc<RefCell<T>>`),
	  which *is* cloneable and preserves Haxe's "values are reusable" expectations.

	What
	- Typing-only handle for `hxrt::process::Process`.

	How
	- `@:native("hxrt::process::Process")` maps this extern to the Rust runtime struct.
**/
@:native("hxrt::process::Process")
extern class ProcessHandle {}
