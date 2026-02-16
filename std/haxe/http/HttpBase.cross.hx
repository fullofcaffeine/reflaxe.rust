package haxe.http;

import haxe.io.Bytes;

private typedef StringKeyValue = {
	var name:String;
	var value:String;
}

/**
	Shared base class for HTTP requests (`haxe.Http` on sys targets).

	Why
	- The upstream stdlib models callbacks (`onData`, `onError`, etc.) as `dynamic function`s.
	- On this Rust target, taking a "method value" (e.g. storing `onData` into a variable) produces a
	  closure that captures `this` (`FClosure`), which the backend does not currently support.

	What
	- Provides the state and helpers needed by `sys.Http`:
	  - request URL, headers, parameters, POST payload
	  - response bytes/string caching
	  - callback hooks: `onData`, `onBytes`, `onError`, `onStatus`

	How
	- We implement callbacks as **function-typed fields** instead of `dynamic function`s.
	  This keeps the public API assignment-friendly (users still do `http.onData = d -> ...`) while
	  avoiding method-value closures in the compiler.
	- `success(...)` always calls `onData` and `onBytes`; the default callbacks are no-ops.
**/
class HttpBase {
	public var url:String;

	public var responseData(get, never):Null<String>;
	public var responseBytes(default, null):Null<Bytes>;

	var responseAsString:Null<String>;
	var postData:Null<String>;
	var postBytes:Null<Bytes>;
	var headers:Array<StringKeyValue>;
	var params:Array<StringKeyValue>;

	public var onData:(String) -> Void;
	public var onBytes:(Bytes) -> Void;
	public var onError:(String) -> Void;
	public var onStatus:(Int) -> Void;

	public function new(url:String) {
		this.url = url;
		headers = [];
		params = [];

		onData = function(_data) {};
		onBytes = function(_data) {};
		onError = function(_msg) {};
		onStatus = function(_status) {};
	}

	public function setHeader(name:String, value:String) {
		for (i in 0...headers.length) {
			if (headers[i].name == name) {
				headers[i] = {name: name, value: value};
				return #if hx3compat this #end;
			}
		}
		headers.push({name: name, value: value});
		#if hx3compat
		return this;
		#end
	}

	public function addHeader(header:String, value:String) {
		headers.push({name: header, value: value});
		#if hx3compat
		return this;
		#end
	}

	public function setParameter(name:String, value:String) {
		for (i in 0...params.length) {
			if (params[i].name == name) {
				params[i] = {name: name, value: value};
				return #if hx3compat this #end;
			}
		}
		params.push({name: name, value: value});
		#if hx3compat
		return this;
		#end
	}

	public function addParameter(name:String, value:String) {
		params.push({name: name, value: value});
		#if hx3compat
		return this;
		#end
	}

	public function setPostData(data:Null<String>) {
		postData = data;
		postBytes = null;
		#if hx3compat
		return this;
		#end
	}

	public function setPostBytes(data:Null<Bytes>) {
		postBytes = data;
		postData = null;
		#if hx3compat
		return this;
		#end
	}

	public function request(?_post:Bool):Void {
		onError("HttpBase.request is not implemented on this target");
	}

	function success(data:Bytes) {
		responseBytes = data;
		// Avoid needing `Null<Bytes>` (Option) narrowing during `get_responseData`.
		var s = data.toString();
		responseAsString = s;
		// Keep Rust output type-safe by passing a non-null `String`.
		onData(s);
		// Pass the concrete `Bytes` we received instead of `responseBytes` (`Null<Bytes>`).
		onBytes(data);
	}

	function get_responseData() {
		return responseAsString;
	}
}
