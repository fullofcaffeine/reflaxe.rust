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

	How
	- These aliases map to `Dynamic` at the unavoidable std API boundary.
	- Code crossing these boundaries should decode to concrete typed structures immediately.
**/
typedef ConstraintValue = Dynamic;

typedef JsonValue = Dynamic;
typedef JsonReplacer = (key:JsonValue, value:JsonValue) -> JsonValue;
