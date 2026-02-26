package reflaxe.rust;

/**
	DynamicBoundary

	Why
	- The backend has a strict `Dynamic`-usage policy and a guard that tracks unavoidable boundary
	  mentions through a tiny allowlist.
	- Scattering `"Dynamic"` literals across analyzers/emitters creates noisy allowlist churn and
	  makes boundary audits harder.

	What
	- Centralized constants/helpers for the unavoidable Haxe dynamic boundary type name.

	How
	- Keep exactly one canonical `Dynamic` literal here.
	- Callers use `typeName()` and `runtimeNamespace()` instead of hardcoding their own strings.
**/
class DynamicBoundary {
	/** Canonical Haxe type name for dynamic boundary lookups. */
	public static inline function typeName():String {
		return "Dynamic";
	}

	/** Canonical Rust runtime namespace backing the dynamic boundary carrier. */
	public static inline function runtimeNamespace():String {
		return "hxrt::dynamic::" + typeName();
	}
}
