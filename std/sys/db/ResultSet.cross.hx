package sys.db;

import sys.db.Types.ResultRow;

/**
	`sys.db.ResultSet` (Rust target override)

	Why
	- `sys.db.Connection.request` returns a `ResultSet` so callers can iterate rows and read columns
	  either by name (`row.field`) or by index (`getResult(n)`).

	What
	- A cursor over rows produced by a query.
	- `next()` returns the next row as `ResultRow` (end-of-result returns `null`).
	- Accessors `getResult*` read from the **current row** (the last row returned by `next()`).

	How
	- The Rust target stores query results in a small runtime container (`hxrt::db::QueryResult`) and
	  exposes a row object as a runtime dynamic-object (`hxrt::dynamic::DynObject`).
	- Field reads on `ResultRow` (`row.field`) are lowered to `hxrt::dynamic::field_get`.
**/
interface ResultSet {
	/**
		Get amount of rows left in this set.
		Depending on a database management system accessing this field may cause
		all rows to be fetched internally. However, it does not affect `next` calls.
	**/
	var length(get, null):Int;

	/**
		Amount of columns in a row.
		Depending on a database management system may return `0` if the query
		did not match any rows.
	**/
	var nfields(get, null):Int;

	/**
		Tells whether there is a row to be fetched.
	**/
	function hasNext():Bool;

	/**
		Fetch next row.
	**/
	function next():ResultRow;

	/**
		Fetch all the rows not fetched yet.
	**/
	function results():List<ResultRow>;

	/**
		Get the value of `n`-th column of the current row.
	**/
	function getResult(n:Int):String;

	/**
		Get the value of `n`-th column of the current row as an integer value.
	**/
	function getIntResult(n:Int):Int;

	/**
		Get the value of `n`-th column of the current row as a float value.
	**/
	function getFloatResult(n:Int):Float;

	/**
		Get the list of column names.
		Depending on a database management system may return `null` if there's no
		more rows to fetch.
	**/
	function getFieldsNames():Null<Array<String>>;
}
