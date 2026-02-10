package hxrt.db;

/**
	Opaque runtime query-result handle (`hxrt::db::QueryResult`).

	Why
	- `sys.db.ResultSet` is stateful: `hasNext()`/`next()` advances a cursor, and methods like
	  `getResult(n)` read from the **current** row.
	- The Rust target keeps driver-specific code in `std/sys/db/*`, but shares the cursor behavior
	  via a small runtime container in `hxrt::db`.

	What
	- An extern marker type used in typed signatures as `HxRef<QueryResultHandle>`.

	How
	- The Rust backend maps `@:native("hxrt::db::QueryResult")` to the real runtime type.
	- All operations are performed via `__rust__` injections that call `hxrt::db::*` helpers.
**/
@:native("hxrt::db::QueryResult")
extern class QueryResultHandle {}

