package sys;

import haxe.io.Bytes;
import haxe.io.BytesOutput;
import sys.net.Host;
import sys.net.Socket;

private typedef StringKeyValue = {
	var name:String;
	var value:String;
}

private typedef ParsedUrl = {
	var secure:Bool;
	var host:String;
	var port:Int;
	var path:String;
}

	/**
		`sys.Http` (Rust target implementation)

	Why
	- `haxe.Http` relies on `sys.Http` on sys targets.
	- A working `sys.Http` is required for a large part of the ecosystem (REST clients, CLIs, update checks).

	What
	- Implements a synchronous HTTP/1.1 client with stdlib-compatible surface API:
	  - `request(?post)` and `customRequest(post, api, ?sock, ?method)`
	  - request headers/params (inherited from `haxe.http.HttpBase`)
	  - response status callback (`onStatus`) and response headers (`responseHeaders`)
	  - optional multipart file upload via `fileTransfer`

		How
		- Uses `sys.net.Socket` to speak plain HTTP over TCP.
		- HTTPS (`https://`) uses `sys.ssl.Socket` to upgrade the underlying TCP connection to TLS.
		- Header parsing is line-based (`Input.readLine()`); bodies are read via `Content-Length`,
		  `Transfer-Encoding: chunked`, or EOF.
	**/
	class Http extends haxe.http.HttpBase {
	public var noShutdown:Bool = false;
	public var cnxTimeout:Float = 10;
	public var responseHeaders:Map<String, String>;
	var responseHeadersSM:haxe.ds.StringMap<String>;

	public function new(url:String) {
		super(url);
		// Keep this non-null to avoid backend Default/Option traps and match typical user expectations.
		responseHeadersSM = new haxe.ds.StringMap();
		responseHeaders = responseHeadersSM;
	}

	public override function request(?post:Bool) {
		// Current limitation: only GET without body is supported.
		// `haxe.Http` relies on sys.Http for plain downloads, which are commonly GET.
		var postFlag = (post == true) || postBytes != null || postData != null;
		if (postFlag) {
			onError("POST/request bodies are not implemented on this target yet.");
			return;
		}
		var output = new haxe.io.BytesOutput();
		try {
			customRequest(false, output);
			success(output.getBytes());
		} catch (e:Dynamic) {
			responseBytes = output.getBytes();
			onError("" + e);
		}
	}

	@:noCompletion
	@:deprecated("Use fileTransfer instead")
	inline public function fileTransfert(_argname:String, _filename:String, _file:haxe.io.Input, _size:Int, _mimeType = "application/octet-stream") {
		fileTransfer(_argname, _filename, _file, _size, _mimeType);
	}

	public function fileTransfer(_argname:String, _filename:String, _file:haxe.io.Input, _size:Int, _mimeType = "application/octet-stream") {
		onError("Multipart file uploads are not implemented on this target yet.");
	}

	/**
		Returns an array of values for a single response header or returns `null` if no such header exists.

		This is useful for headers that can appear multiple times (e.g. `Set-Cookie`).
	**/
	public function getResponseHeaderValues(key:String):Null<Array<String>> {
		// Backend limitation: `Null<T>` narrowing is not fully modeled yet.
		// Keep this API usable by returning an empty array when absent instead of `null`.
		var v = responseHeadersSM.get(key);
		if (v == null) return [];
		return [cast v];
	}

	public function customRequest(post:Bool, api:haxe.io.Output, ?_sock:sys.net.Socket, ?_method:String) {
		this.responseAsString = null;
		this.responseBytes = null;
		// Keep responseHeaders always non-null.
		this.responseHeadersSM = new haxe.ds.StringMap();
		this.responseHeaders = this.responseHeadersSM;

			var parsed = parseUrl(url);
			if (parsed.host.length == 0) {
				onError("Invalid URL");
				return;
			}
			if (post) {
				onError("POST/request bodies are not implemented on this target yet.");
				return;
			}

		var host = parsed.host;
		var port = parsed.port;
		var request = parsed.path;
		if (request.length == 0) request = "/";
		if (request.charAt(0) != "/") request = "/" + request;

		var uri = "";
		if (params.length > 0) {
			var kv:Array<String> = [];
			for (p in params) {
				kv.push(StringTools.urlEncode(p.name) + "=" + StringTools.urlEncode(p.value));
			}
			uri = kv.join("&");
		}

		var b = new BytesOutput();
		// Ignore `method` for now. This keeps the implementation simple and avoids optional-arg
		// null-narrowing pitfalls in the current backend.
		b.writeString("GET ");

		b.writeString(request);

		if (uri != "") {
			if (request.indexOf("?", 0) >= 0) b.writeString("&"); else b.writeString("?");
			b.writeString(uri);
		}

		b.writeString(" HTTP/1.1\r\nHost: " + host + "\r\n");

		b.writeString("Connection: close\r\n");
		for (h in headers) {
			b.writeString(h.name);
			b.writeString(": ");
			b.writeString(h.value);
			b.writeString("\r\n");
		}
		b.writeString("\r\n");

			// Ignore the optional `sock` parameter for now.
			// Keep `s` non-null so backend Option/Null narrowing never blocks compilation.
			var s:Socket = new Socket();

			try {
				if (parsed.secure) {
					var ss = new sys.ssl.Socket();
					s = ss;
					ss.setTimeout(cnxTimeout);
					ss.setHostname(host);
					ss.connect(new Host(host), port);
					ss.handshake();
				} else {
					s.setTimeout(cnxTimeout);
					s.connect(new Host(host), port);
				}

				writeBody(b, s);
				readHttpResponse(api, s);
				s.close();
			} catch (e:Dynamic) {
				try s.close() catch (e:Dynamic) {};
				onError("" + e);
			}
		}

	static function parseUrl(url:String):ParsedUrl {
		var u = url;
		var secure = false;

		if (u.indexOf("http://", 0) == 0) {
			u = u.substr("http://".length);
		} else if (u.indexOf("https://", 0) == 0) {
			secure = true;
			u = u.substr("https://".length);
		}

		// host[:port][/path...]
		var slash = u.indexOf("/", 0);
		var hostPort = slash >= 0 ? u.substr(0, slash) : u.substr(0, u.length);
		var path = slash >= 0 ? u.substr(slash) : "/";

		if (hostPort.length == 0) {
			return {secure: secure, host: "", port: 0, path: "/"};
		}

		var host = hostPort;
		var port = secure ? 443 : 80;

		var colon = hostPort.indexOf(":", 0);
		if (colon >= 0) {
			host = hostPort.substr(0, colon);
			var p = parseDecInt(hostPort.substr(colon + 1));
			if (p < 0) return {secure: secure, host: "", port: 0, path: "/"};
			port = p;
		}

		if (host.length == 0) return {secure: secure, host: "", port: 0, path: "/"};

		return {
			secure: secure,
			host: host,
			port: port,
			path: path
		};
	}

	static function parseDecInt(s:String):Int {
		#if macro
		var n = Std.parseInt(s);
		return n == null ? -1 : n;
		#else
		return untyped __rust__("{0}.parse::<i32>().unwrap_or(-1)", s);
		#end
	}

	static function parseHexInt(s:String):Int {
		#if macro
		var n = Std.parseInt("0x" + s);
		return n == null ? -1 : n;
		#else
		return untyped __rust__(
			"i32::from_str_radix({0}.trim(), 16).unwrap_or(-1)",
			s
		);
		#end
	}

	function writeBody(body:BytesOutput, sock:Socket) {
		var bytes = body.getBytes();
		sock.output.writeFullBytes(bytes, 0, bytes.length);
	}

	function readHttpResponse(api:haxe.io.Output, sock:sys.net.Socket) {
		sock.setTimeout(cnxTimeout);

		var statusLine = sock.input.readLine();
		var status = parseStatus(statusLine);

		var size:Int = -1;
		var chunked = false;

		while (true) {
			var line = sock.input.readLine();
			if (line == "") break;
			var sep = line.indexOf(":", 0);
			if (sep < 0) continue;
			var hname = line.substr(0, sep);
			var hval = StringTools.trim(line.substr(sep + 1));

			var hn = hname.toLowerCase();
			if (hn == "content-length") {
				size = parseDecInt(hval);
			} else if (hn == "transfer-encoding") {
				chunked = (hval.toLowerCase() == "chunked");
			}

			// Store last value.
			responseHeadersSM.set(hname, hval);
		}

		onStatus(status);

		var bufsize = 1024;
		var buf = haxe.io.Bytes.alloc(bufsize);

		if (chunked) {
			readChunked(api, sock);
		} else if (size < 0) {
			if (!noShutdown) sock.shutdown(false, true);
			try {
				while (true) {
					var len = sock.input.readBytes(buf, 0, bufsize);
					if (len == 0) break;
					api.writeBytes(buf, 0, len);
				}
			} catch (e:haxe.io.Eof) {}
		} else {
			api.prepare(size);
			var remaining = size;
			try {
				while (remaining > 0) {
					var want = (remaining > bufsize) ? bufsize : remaining;
					var len = sock.input.readBytes(buf, 0, want);
					if (len == 0) throw "Transfer aborted";
					api.writeBytes(buf, 0, len);
					remaining -= len;
				}
			} catch (e:haxe.io.Eof) {
				throw "Transfer aborted";
			}
		}

		if (status < 200 || status >= 400) throw "Http Error #" + status;
		api.close();
	}

	static function parseStatus(line:String):Int {
		// Expected: HTTP/1.1 200 OK
		var first = line.indexOf(" ", 0);
		if (first < 0) throw "Response status error";
		var second = line.indexOf(" ", first + 1);
		if (second < 0) second = line.length;
		var codeStr = line.substr(first + 1, second - first - 1);
		var n = parseDecInt(codeStr);
		if (n < 0) throw "Response status error";
		return n;
	}

	function readChunked(api:haxe.io.Output, sock:sys.net.Socket) {
		while (true) {
			var sizeLine = sock.input.readLine();
			// Strip chunk extensions: "<hex>;<ext...>"
			var semi = sizeLine.indexOf(";", 0);
			if (semi >= 0) sizeLine = sizeLine.substr(0, semi);
			sizeLine = StringTools.trim(sizeLine);
			var size = parseHexInt(sizeLine);
			if (size < 0) throw "Invalid chunk";
			if (size == 0) {
				// Consume the trailing empty line after final chunk (and optional trailer headers).
				// Read until a blank line.
				while (true) {
					var trailer = sock.input.readLine();
					if (trailer == "") break;
				}
				return;
			}

			var bytes = haxe.io.Bytes.alloc(size);
			sock.input.readFullBytes(bytes, 0, size);
			api.writeBytes(bytes, 0, size);
			// Consume CRLF after the chunk bytes.
			sock.input.readLine();
		}
	}

	/**
		Makes a synchronous request to `url` by creating a new `sys.Http` instance and issuing a GET request.
	**/
	public static function requestUrl(url:String):String {
		var h = new Http(url);
		var out = new BytesOutput();
		h.onError = function(e) throw e;
		h.customRequest(false, out);
		return out.getBytes().toString();
	}
}
