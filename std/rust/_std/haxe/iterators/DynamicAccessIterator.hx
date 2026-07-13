package haxe.iterators;

import haxe.DynamicAccess;

/**
	`haxe.iterators.DynamicAccessIterator` for the Rust target.

	Why
	- `DynamicAccess.iterator()` exposes this nominal class in Haxe typed AST.
	- Upstream std modules are available for typing but are not emitted into generated Rust crates, so
	  the Rust target must ship the public iterator implementation that its generated types reference.
	- A materialized value snapshot would be incorrect: upstream Haxe snapshots the keys at construction
	  but reads each value from the source object when `next()` runs.

	What
	- Implements the upstream value-iterator contract over `haxe.DynamicAccess<T>`.
	- Keeps one cursor per iterator object, so aliases observe the same progress.

	How
	- Captures `access.keys()` once in the constructor.
	- Retains the typed `DynamicAccess<T>` source and performs the unavoidable dynamic field lookup only
	  at the collection boundary in `next()`, returning immediately to the concrete `T` contract.
	- Uses the normal generated class representation. When this nominal value crosses the structural
	  iterator ABI, the compiler may use the generic callback-backed `Iter<T>` bridge; this class adds
	  no target injection, native facade, or DynamicAccess-specific runtime helper.
**/
@:rustGeneric("T: Clone + Send + Sync + 'static + std::fmt::Debug")
class DynamicAccessIterator<T> {
	final access:DynamicAccess<T>;
	final keys:Array<String>;
	var index:Int;

	/**
		Creates a cursor over the keys present at construction time.

		Why / What / How
		- Matching upstream behavior requires a stable key list while retaining the live source object.
		- The constructor snapshots only `access.keys()` and initializes the shared cursor to zero.
	**/
	public inline function new(access:DynamicAccess<T>) {
		this.access = access;
		this.keys = access.keys();
		this.index = 0;
	}

	/**
		Reports whether the captured key list contains another entry.

		Why / What / How
		- Cursor state belongs to this iterator object and is therefore shared by Haxe aliases.
		- The check does not read or advance the source value.
	**/
	public inline function hasNext():Bool {
		return index < keys.length;
	}

	/**
		Reads the live value for the next captured key.

		Why / What / How
		- `DynamicAccess` is an explicitly dynamic collection boundary, but callers receive concrete `T`.
		- Advance the cursor once, use the captured key for the existing typed index access, and return the
		  resulting value without storing a second materialized copy.
	**/
	public inline function next():T {
		return access[keys[index++]];
	}
}
