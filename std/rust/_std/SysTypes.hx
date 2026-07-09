import haxe.BoundaryTypes.SysPrintBoundaryValue;

/**
	`Sys` boundary value aliases (Rust target override)

	Why
	- Upstream `Sys.print` and `Sys.println` accept untyped values by contract.
	- We still want backend code to clearly mark this as a boundary and keep
	  implementation internals strongly typed.

	What
	- `SysPrintValue`: value accepted by `Sys.print` and `Sys.println`.

	How
	- This alias delegates to `haxe.BoundaryTypes.SysPrintBoundaryValue` for upstream compatibility.
	- Treat it as a boundary type: convert to concrete typed shapes as soon as
	  practical in non-API code.
**/
typedef SysPrintValue = SysPrintBoundaryValue;
