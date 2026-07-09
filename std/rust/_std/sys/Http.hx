package sys;

import haxe.io.Bytes;
import haxe.io.BytesOutput;
import haxe.io.Input;
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

private typedef PendingUpload = {
	var param:String;
	var filename:String;
	var io:Input;
	var size:Int;
	var mimeType:String;
}

/**
	`sys.Http` (Rust target implementation)

	Why
	- `haxe.Http` relies on `sys.Http` on sys targets, so portable parity depends on this class matching upstream request semantics.
	- Tier1 stdlib parity requires real support for request bodies, duplicate response headers, and multipart file uploads.

	What
	- Implements the upstream synchronous HTTP/1.1 request contract for the Rust target:
	  - GET/POST request selection
	  - `postData` / `postBytes` bodies
	  - multipart `fileTransfer(...)`
	  - duplicate response-header collection for `getResponseHeaderValues(...)`
	  - plain HTTP via `sys.net.Socket` and HTTPS via `sys.ssl.Socket`

	How
	- Request assembly follows upstream `sys.Http` closely so behavior stays portable across Haxe backends.
	- The type surface stays strongly typed; native/socket boundaries remain localized in this std override.
	- Response parsing keeps the Rust-friendly line-based body reader already used by this backend while restoring upstream header semantics.
**/
class Http extends haxe.http.HttpBase {
	public var noShutdown:Bool = false;
	public var cnxTimeout:Float = 10;
	public var responseHeaders:Map<String, String>;

	var responseHeadersSM:haxe.ds.StringMap<String>;
	var responseHeadersSameKey:haxe.ds.StringMap<Array<String>>;
	var file:Null<PendingUpload>;

	public function new(url:String) {
		super(url);
		responseHeadersSM = new haxe.ds.StringMap();
		responseHeadersSameKey = new haxe.ds.StringMap();
		responseHeaders = responseHeadersSM;
	}

	public override function request(?post:Bool) {
		var output = new BytesOutput();
		var old = onError;
		var outputForError = output;
		var oldOnError = old;
		var err = false;
		onError = function(msg) {
			responseBytes = outputForError.getBytes();
			err = true;
			oldOnError(msg);
		};
		var postFlag = (post == true) || postBytes != null || postData != null || file != null;
		customRequest(postFlag, output);
		if (!err)
			success(output.getBytes());
	}

	@:noCompletion
	@:deprecated("Use fileTransfer instead")
	inline public function fileTransfert(argname:String, filename:String, file:haxe.io.Input, size:Int, mimeType = "application/octet-stream") {
		fileTransfer(argname, filename, file, size, mimeType);
	}

	/**
		Stores multipart upload metadata until the next `request(...)` / `customRequest(...)` call.

		Why
		- Upstream `sys.Http` accumulates form fields first and serializes the multipart body during request emission.
		- Doing the same here preserves field ordering and avoids prematurely consuming the caller-provided `Input`.

		What
		- Records one pending file upload payload.

		How
		- The actual bytes are written in `writeBody(...)` once headers and boundary are finalized.
	**/
	public function fileTransfer(argname:String, filename:String, file:haxe.io.Input, size:Int, mimeType = "application/octet-stream") {
		this.file = {
			param: argname,
			filename: filename,
			io: file,
			size: size,
			mimeType: mimeType
		};
	}

	/**
		Returns every response-header value recorded for `key`.

		Why
		- Some headers such as `Set-Cookie` are legally repeated and cannot be represented faithfully by the single-value `responseHeaders` map.

		What
		- Returns `null` if the header is absent, `[value]` for a single occurrence, or all values for repeated headers.

		How
		- `responseHeaders` stores the last-seen value for compatibility.
		- `responseHeadersSameKey` stores additional occurrences so duplicate headers remain observable.
	**/
	public function getResponseHeaderValues(key:String):Null<Array<String>> {
		var repeated = responseHeadersSameKey.get(key);
		if (repeated != null)
			return repeated;
		var single = responseHeadersSM.get(key);
		return single == null ? null : [single];
	}

	public function customRequest(post:Bool, api:haxe.io.Output, ?_sock:sys.net.Socket, ?method:String) {
		this.responseAsString = null;
		this.responseBytes = null;
		this.responseHeadersSM = new haxe.ds.StringMap();
		this.responseHeadersSameKey = new haxe.ds.StringMap();
		this.responseHeaders = this.responseHeadersSM;

		var parsed = parseUrl(url);
		if (parsed.host.length == 0) {
			onError("Invalid URL");
			return;
		}

		var host = parsed.host;
		var port = parsed.port;
		var request = parsed.path;
		if (request.length == 0)
			request = "/";
		if (request.charAt(0) != "/")
			request = "/" + request;

		var multipart = (file != null);
		var boundary:Null<String> = null;
		var uri:Null<String> = if (multipart) {
			post = true;
			boundary = createBoundary();
			buildMultipartPrefix(boundary, file);
		} else {
			buildParamsString();
		};

		var requestBytes = new BytesOutput();
		if (method != null) {
			requestBytes.writeString(method);
			requestBytes.writeString(" ");
		} else if (post) {
			requestBytes.writeString("POST ");
		} else {
			requestBytes.writeString("GET ");
		}

		requestBytes.writeString(request);
		if (!post && uri != null) {
			if (request.indexOf("?", 0) >= 0)
				requestBytes.writeString("&");
			else
				requestBytes.writeString("?");
			requestBytes.writeString(uri);
		}
		requestBytes.writeString(" HTTP/1.1\r\nHost: " + host + "\r\n");

		if (postData != null) {
			postBytes = Bytes.ofString(postData);
			postData = null;
		}
		if (postBytes != null) {
			requestBytes.writeString("Content-Length: " + postBytes.length + "\r\n");
		} else if (post && uri != null) {
			if (multipart || !hasHeader("Content-Type")) {
				requestBytes.writeString("Content-Type: ");
				if (multipart) {
					requestBytes.writeString("multipart/form-data; boundary=");
					requestBytes.writeString(boundary);
				} else {
					requestBytes.writeString("application/x-www-form-urlencoded");
				}
				requestBytes.writeString("\r\n");
			}
			if (multipart) {
				requestBytes.writeString("Content-Length: " + (uri.length + file.size + boundary.length + 6) + "\r\n");
			} else {
				requestBytes.writeString("Content-Length: " + uri.length + "\r\n");
			}
		}

		requestBytes.writeString("Connection: close\r\n");
		for (h in headers) {
			requestBytes.writeString(h.name);
			requestBytes.writeString(": ");
			requestBytes.writeString(h.value);
			requestBytes.writeString("\r\n");
		}
		requestBytes.writeString("\r\n");
		if (postBytes != null) {
			requestBytes.writeFullBytes(postBytes, 0, postBytes.length);
		} else if (post && uri != null) {
			requestBytes.writeString(uri);
		}

		if (_sock != null)
			performRequest(_sock, host, port, requestBytes, api, multipart, boundary);
		else
			performRequest(createSocket(parsed.secure, host), host, port, requestBytes, api, multipart, boundary);
		file = null;
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

		var slash = u.indexOf("/", 0);
		var hostPort = slash >= 0 ? u.substr(0, slash) : u.substr(0, u.length);
		var path = slash >= 0 ? u.substr(slash) : "/";
		if (hostPort.length == 0)
			return {
				secure: secure,
				host: "",
				port: 0,
				path: "/"
			};

		var host = hostPort;
		var port = secure ? 443 : 80;
		var colon = hostPort.indexOf(":", 0);
		if (colon >= 0) {
			host = hostPort.substr(0, colon);
			var parsedPort = parseDecInt(hostPort.substr(colon + 1));
			if (parsedPort < 0)
				return {
					secure: secure,
					host: "",
					port: 0,
					path: "/"
				};
			port = parsedPort;
		}
		if (host.length == 0)
			return {
				secure: secure,
				host: "",
				port: 0,
				path: "/"
			};
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
		return untyped __rust__("i32::from_str_radix({0}.trim(), 16).unwrap_or(-1)", s);
		#end
	}

	function buildParamsString():Null<String> {
		if (params.length == 0)
			return null;
		var encoded = new Array<String>();
		for (p in params)
			encoded.push(StringTools.urlEncode(p.name) + "=" + StringTools.urlEncode(p.value));
		return encoded.join("&");
	}

	function buildMultipartPrefix(boundary:String, upload:PendingUpload):String {
		var b = new StringBuf();
		for (p in params) {
			b.add("--");
			b.add(boundary);
			b.add("\r\n");
			b.add('Content-Disposition: form-data; name="');
			b.add(p.name);
			b.add('"');
			b.add("\r\n\r\n");
			b.add(p.value);
			b.add("\r\n");
		}
		b.add("--");
		b.add(boundary);
		b.add("\r\n");
		b.add('Content-Disposition: form-data; name="');
		b.add(upload.param);
		b.add('"; filename="');
		b.add(upload.filename);
		b.add('"');
		b.add("\r\n");
		b.add("Content-Type: ");
		b.add(upload.mimeType);
		b.add("\r\n\r\n");
		return b.toString();
	}

	function createBoundary():String {
		return "---------------------------reflaxe-rust-boundary";
	}

	function hasHeader(name:String):Bool {
		for (h in headers) {
			if (h.name == name)
				return true;
		}
		return false;
	}

	function createSocket(secure:Bool, host:String):Socket {
		if (secure) {
			var ssl = new sys.ssl.Socket();
			ssl.setTimeout(cnxTimeout);
			ssl.setHostname(host);
			return ssl;
		}
		var sock = new Socket();
		sock.setTimeout(cnxTimeout);
		return sock;
	}

	function performRequest(sock:Socket, host:String, port:Int, requestBytes:BytesOutput, api:haxe.io.Output, multipart:Bool, boundary:Null<String>) {
		try {
			sock.connect(new Host(host), port);
			if (multipart) {
				writeBody(requestBytes, sock);
				writeMultipartTail(file.io, file.size, boundary, sock);
			} else {
				writeBody(requestBytes, sock);
			}
			readHttpResponse(api, sock);
			sock.close();
		} catch (e:Dynamic) {
			try
				sock.close()
			catch (_:Dynamic) {};
			onError(Std.string(e));
		}
	}

	/**
		Writes the assembled request bytes and optional multipart payload to the socket.

		Why
		- Multipart uploads cannot be fully buffered in the generic request prefix because the file content arrives through `haxe.io.Input`.

		What
		- Flushes header/body bytes first, then streams the file payload and closing boundary.

		How
		- The `BytesOutput` prefix already contains the multipart field prelude and regular request body data.
		- When `boundary` is non-null, this method streams `fileInput` directly and appends the final `--boundary--` marker.
	**/
	function writeBody(body:BytesOutput, sock:Socket) {
		var bytes = body.getBytes();
		sock.output.writeFullBytes(bytes, 0, bytes.length);
	}

	function writeMultipartTail(fileInput:Input, fileSize:Int, boundary:String, sock:Socket) {
		var remaining = fileSize;
		var bufsize = 4096;
		var buf = Bytes.alloc(bufsize);
		while (remaining > 0) {
			var want = remaining > bufsize ? bufsize : remaining;
			var len = 0;
			try {
				len = fileInput.readBytes(buf, 0, want);
			} catch (_:haxe.io.Eof) {
				break;
			}
			sock.output.writeFullBytes(buf, 0, len);
			remaining -= len;
		}
		sock.output.writeString("\r\n");
		sock.output.writeString("--");
		sock.output.writeString(boundary);
		sock.output.writeString("--");
	}

	function readHttpResponse(api:haxe.io.Output, sock:sys.net.Socket) {
		sock.setTimeout(cnxTimeout);
		var statusLine = sock.input.readLine();
		var status = parseStatus(statusLine);
		var size:Int = -1;
		var chunked = false;
		while (true) {
			var line = sock.input.readLine();
			if (line == "")
				break;
			var sep = line.indexOf(":", 0);
			if (sep < 0)
				continue;
			var hname = line.substr(0, sep);
			var hval = StringTools.trim(line.substr(sep + 1));
			var previous = responseHeadersSM.get(hname);
			if (previous != null) {
				var repeated = responseHeadersSameKey.get(hname);
				if (repeated == null) {
					repeated = [previous];
					responseHeadersSameKey.set(hname, repeated);
				}
				repeated.push(hval);
			}
			responseHeadersSM.set(hname, hval);
			switch (hname.toLowerCase()) {
				case "content-length":
					size = parseDecInt(hval);
				case "transfer-encoding":
					chunked = (hval.toLowerCase() == "chunked");
				default:
			}
		}

		onStatus(status);
		var bufsize = 1024;
		var buf = Bytes.alloc(bufsize);
		if (chunked) {
			readChunked(api, sock);
		} else if (size < 0) {
			if (!noShutdown)
				sock.shutdown(false, true);
			try {
				while (true) {
					var len = sock.input.readBytes(buf, 0, bufsize);
					if (len == 0)
						break;
					api.writeBytes(buf, 0, len);
				}
			} catch (_:haxe.io.Eof) {}
		} else {
			api.prepare(size);
			var remaining = size;
			try {
				while (remaining > 0) {
					var want = (remaining > bufsize) ? bufsize : remaining;
					var len = sock.input.readBytes(buf, 0, want);
					if (len == 0)
						throw "Transfer aborted";
					api.writeBytes(buf, 0, len);
					remaining -= len;
				}
			} catch (_:haxe.io.Eof) {
				throw "Transfer aborted";
			}
		}
		if (status < 200 || status >= 400)
			throw "Http Error #" + status;
		api.close();
	}

	static function parseStatus(line:String):Int {
		var first = line.indexOf(" ", 0);
		if (first < 0)
			throw "Response status error";
		var second = line.indexOf(" ", first + 1);
		if (second < 0)
			second = line.length;
		var codeStr = line.substr(first + 1, second - first - 1);
		var n = parseDecInt(codeStr);
		if (n < 0)
			throw "Response status error";
		return n;
	}

	function readChunked(api:haxe.io.Output, sock:sys.net.Socket) {
		while (true) {
			var sizeLine = sock.input.readLine();
			var semi = sizeLine.indexOf(";", 0);
			if (semi >= 0)
				sizeLine = sizeLine.substr(0, semi);
			sizeLine = StringTools.trim(sizeLine);
			var size = parseHexInt(sizeLine);
			if (size < 0)
				throw "Invalid chunk";
			if (size == 0) {
				while (true) {
					var trailer = sock.input.readLine();
					if (trailer == "")
						break;
				}
				return;
			}
			var bytes = Bytes.alloc(size);
			sock.input.readFullBytes(bytes, 0, size);
			api.writeBytes(bytes, 0, size);
			sock.input.readLine();
		}
	}

	/**
		Makes a synchronous request to `url` by creating a fresh `sys.Http` instance.
	**/
	public static function requestUrl(url:String):String {
		var h = new Http(url);
		var out = new BytesOutput();
		h.onError = function(e) throw e;
		h.customRequest(false, out);
		return out.getBytes().toString();
	}
}
