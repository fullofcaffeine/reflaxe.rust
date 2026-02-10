package haxe;

/**
	`haxe.Constraints` (Rust target override)

	Why
	- The stdlib uses `haxe.Constraints.*` as type-parameter constraints in several places:
	  - `haxe.Constraints.Function` is referenced by `Reflect` and formatting code.
	  - `haxe.Constraints.IMap` is the shared contract behind `Map<K, V>` and `haxe.ds.*Map` types.
	- This Rust backend only emits code for sources in this repo (`std/` overrides plus user code),
	  so we must provide the required constraint types here.

	What
	- Implements the most commonly used constraint types from Haxe 4.3.x:
	  - `Function`, `FlatEnum`, `NotVoid`, `Constructible<T>`
	  - `IMap<K, V>`

	How
	- These are compile-time constraints. Their runtime representation is `Dynamic` where applicable.
	- `IMap` is implemented by concrete map types such as `haxe.ds.StringMap`.
**/

/**
	This type unifies with any function type.

	If used as a real type, the underlying type is `Dynamic`.
**/
@:callable
abstract Function(Dynamic) {}

/**
	This type unifies with an enum instance if all constructors of the enum require no arguments.
**/
abstract FlatEnum(Dynamic) {}

/**
	This type unifies with anything but `Void`.
**/
abstract NotVoid(Dynamic) {}

/**
	This type unifies with any instance of classes that have a constructor which unifies with `T`.
**/
abstract Constructible<T>(Dynamic) {}

/**
	A minimal map interface used by `Map<K, V>` and concrete map implementations.

	Notes for this Rust backend
	- Methods that return `Null<T>` map to `Option<T>` in Rust output.
	- Iteration methods are primarily intended for Haxe `for` loops.
**/
interface IMap<K, V> {
	function get(k:K):Null<V>;
	function set(k:K, v:V):Void;
	function exists(k:K):Bool;
	function remove(k:K):Bool;
	function keys():Iterator<K>;
	function iterator():Iterator<V>;
	function keyValueIterator():KeyValueIterator<K, V>;
	function copy():IMap<K, V>;
	function toString():String;
	function clear():Void;
}
