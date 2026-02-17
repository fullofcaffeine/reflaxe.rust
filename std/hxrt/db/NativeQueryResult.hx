package hxrt.db;

import rust.HxRef;
import rust.Ref;
import sys.db.Types.ResultRow;

/**
	`hxrt.db.NativeQueryResult` (Rust runtime binding)

	Why
	- `sys.db.ResultSet` methods are implemented by calling runtime helpers in `hxrt::db`.
	- Calling those helpers through raw `untyped __rust__` creates avoidable typing holes and
	  warning noise in backend logs.

	What
	- Typed extern bindings for the query-result helper functions.

	How
	- Maps directly to `hxrt::db::*`.
	- Uses `Ref<HxRef<QueryResultHandle>>` so the backend emits borrowed `&` arguments.
**/
@:native("hxrt::db")
extern class NativeQueryResult {
	@:native("query_result_length")
	public static function length(res:Ref<HxRef<QueryResultHandle>>):Int;

	@:native("query_result_nfields")
	public static function nfields(res:Ref<HxRef<QueryResultHandle>>):Int;

	@:native("query_result_has_next")
	public static function hasNext(res:Ref<HxRef<QueryResultHandle>>):Bool;

	@:native("query_result_next_row_object")
	public static function nextRowObject(res:Ref<HxRef<QueryResultHandle>>):ResultRow;

	@:native("query_result_get_result")
	public static function getResult(res:Ref<HxRef<QueryResultHandle>>, n:Int):String;

	@:native("query_result_get_int_result")
	public static function getIntResult(res:Ref<HxRef<QueryResultHandle>>, n:Int):Int;

	@:native("query_result_get_float_result")
	public static function getFloatResult(res:Ref<HxRef<QueryResultHandle>>, n:Int):Float;

	@:native("query_result_fields")
	public static function fields(res:Ref<HxRef<QueryResultHandle>>):Array<String>;
}
