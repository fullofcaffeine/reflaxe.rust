package haxe;

/**
	`haxe` boundary value aliases (Rust target override)

	Why
	- Some upstream `haxe.*` std APIs are intentionally untyped and must remain that way for
	  cross-target compatibility (notably JSON payloads and constraint runtime carriers).
	- We still want implementation files to avoid raw `Dynamic` mentions and keep boundaries explicit.

	What
	- `ConstraintValue`: runtime carrier for `haxe.Constraints.*` abstracts.
	- `JsonValue`: runtime JSON payload for `haxe.Json` and `hxrt.json.NativeJson`.
	- `JsonReplacer`: replacer callback shape used by `haxe.Json.stringify`.
	- `SysPrintBoundaryValue`: payload accepted by `Sys.print` / `Sys.println`.
	- `SocketCustomBoundaryValue`: payload stored in `sys.net.Socket.custom`.
	- `ThreadMessageBoundaryValue`: payload passed through `sys.thread.Thread` message APIs.
	- `SqlBoundaryValue`: value accepted by `sys.db.Connection.addValue`.
	- `DbResultRowBoundaryValue`: row object returned by `sys.db.ResultSet`.
	- `StringBufAddBoundaryValue`: value accepted by `StringBuf.add`.
	- `ExceptionBoundaryValue`: payload captured by legacy catch-all helpers.

	How
	- These aliases map to `Dynamic` at the unavoidable std API boundary.
	- Code crossing these boundaries should decode to concrete typed structures immediately.
**/
typedef ConstraintValue = Dynamic;

typedef JsonValue = Dynamic;
typedef JsonReplacer = (key:JsonValue, value:JsonValue) -> JsonValue;
typedef SysPrintBoundaryValue = Dynamic;
typedef SocketCustomBoundaryValue = Dynamic;
typedef ThreadMessageBoundaryValue = Dynamic;
typedef SqlBoundaryValue = Dynamic;
typedef DbResultRowBoundaryValue = Dynamic;
typedef StringBufAddBoundaryValue = Dynamic;
typedef ExceptionBoundaryValue = Dynamic;
