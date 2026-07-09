package sys.db;

import haxe.BoundaryTypes.DbResultRowBoundaryValue;
import haxe.BoundaryTypes.SqlBoundaryValue;

/**
	`sys.db` boundary value aliases (Rust target override)

	Why
	- The upstream `sys.db` API exposes untyped SQL values and row objects at the interface boundary.
	- We still want the Rust target override code to stay explicit and self-documenting about where
	  untyped data is intentionally allowed.

	What
	- `SqlValue`: value accepted by `Connection.addValue(...)`.
	- `ResultRow`: row object returned by `ResultSet.next()` and `ResultSet.results()`.

	How
	- Both aliases delegate to `haxe.BoundaryTypes` compatibility aliases to preserve upstream `sys.db` behavior.
	- Compiler/runtime code should treat these aliases as **boundary types** and immediately convert
	  to concrete typed structures where practical.
**/
typedef SqlValue = SqlBoundaryValue;

typedef ResultRow = DbResultRowBoundaryValue;
