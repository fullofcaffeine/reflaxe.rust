package haxe.http;

import haxe.io.Bytes;

private typedef StringKeyValue = {
	var name:String;
	var value:String;
}

/**
	Shared base class for HTTP requests (`haxe.Http` on sys targets).

	Why
	- Upstream Haxe models the callback hooks (`onData`, `onBytes`, `onError`, `onStatus`) as
	  `dynamic function`s, not plain function-typed fields.
	- That design matters because callers can both assign callbacks (`http.onData = ...`) and
	  override the hooks in subclasses.
	- This Rust target previously rewrote those hooks into function fields as a temporary workaround
	  for missing `this.method` / instance-method value support. The compiler now supports that
	  lowering directly, so the workaround would only preserve a broken API contract.

	What
	- Restores the upstream callback surface:
	  - callback hooks are `dynamic function`s
	  - `hasOnData()` detects whether `onData` was overridden/assigned
	  - `success(...)` mirrors upstream behavior and only forces string decoding when needed

	How
	- `emptyOnData = onData` captures the default method value in the constructor.
	- `Reflect.compareMethods(...)` is used only inside framework stdlib code to detect whether
	  the current `onData` differs from the default no-op callback.
	- The rest of the class stays strongly typed; callers still interact with typed `String` /
	  `Bytes` callbacks and do not cross any untyped boundary directly.
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
	final emptyOnData:(String) -> Void;

	public function new(url:String) {
		this.url = url;
		headers = [];
		params = [];
		emptyOnData = onData;
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

	public dynamic function onData(data:String) {}

	public dynamic function onBytes(data:Bytes) {}

	public dynamic function onError(msg:String) {}

	public dynamic function onStatus(status:Int) {}

	function hasOnData():Bool {
		return !Reflect.compareMethods(onData, emptyOnData);
	}

	function success(data:Bytes) {
		responseBytes = data;
		responseAsString = null;
		if (hasOnData()) {
			var s = responseData;
			if (s != null)
				onData(s);
		}
		onBytes(data);
	}

	function get_responseData() {
		if (responseAsString == null && responseBytes != null) {
			responseAsString = responseBytes.getString(0, responseBytes.length, UTF8);
		}
		return responseAsString;
	}
}
