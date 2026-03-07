import haxe.io.Bytes;
import sys.Http;
import sys.net.Host;
import sys.net.Socket;
import sys.thread.Lock;
import sys.thread.Thread;

private typedef CapturedRequest = {
	var method:String;
	var contentType:Null<String>;
	var body:String;
}

class Main {
	static function main():Void {
		final form = runRequest(function(port) {
			final http = new Http("http://127.0.0.1:" + port + "/submit");
			http.setParameter("q", "ok");
			http.addParameter("page", "1");
			return {
				http: http,
				run: function() http.request(true)
			};
		}, "form-ok");

		Sys.println("formMethod=" + form.capture.method);
		Sys.println("formType=" + stringifyNull(form.capture.contentType));
		Sys.println("formBody=" + form.capture.body);
		Sys.println("cookies=" + joinHeaderValues(form.http.getResponseHeaderValues("Set-Cookie")));
		Sys.println("missingWasNull=" + Std.string(form.http.getResponseHeaderValues("X-Missing") == null));
		Sys.println("formResponse=" + form.responseData);

		final multipart = runRequest(function(port) {
			final http = new Http("http://127.0.0.1:" + port + "/upload");
			http.setParameter("token", "abc");
			final fileBytes = Bytes.ofString("file-body");
			http.fileTransfer("upload", "note.txt", new StaticBytesInput(fileBytes), fileBytes.length, "text/plain");
			return {
				http: http,
				run: function() http.request(true)
			};
		}, "upload-ok");

		final boundary = extractBoundary(multipart.capture.contentType);
		Sys.println("multipartMethod=" + multipart.capture.method);
		Sys.println("multipartType=" + stringifyNull(multipart.capture.contentType));
		Sys.println("multipartHasToken="
			+ Std.string(multipart.capture.body.indexOf('name="token"') >= 0 && multipart.capture.body.indexOf("\r\n\r\nabc\r\n") >= 0));
		Sys.println("multipartHasFile="
			+ Std.string(multipart.capture.body.indexOf('name="upload"; filename="note.txt"') >= 0
				&& multipart.capture.body.indexOf("file-body") >= 0));
		Sys.println("multipartHasClosingBoundary=" + Std.string(boundary != null
			&& StringTools.endsWith(multipart.capture.body, "--" + boundary + "--")));
		Sys.println("multipartResponse=" + multipart.responseData);
	}

	static function runRequest(build:Int->{http: Http, run: Void -> Void}, responseBody:String):{
		http:Http,
		capture:CapturedRequest,
		responseData:String
	} {
		final server = new Socket();
		server.bind(new Host("127.0.0.1"), 0);
		server.listen(1);

		final port = server.host().port;
		final capture:CapturedRequest = {
			method: "",
			contentType: null,
			body: ""
		};
		final done = new Lock();
		final captureForThread = capture;
		final doneForThread = done;

		Thread.create(() -> {
			final client = server.accept();
			final request = readRequest(client);
			captureForThread.method = request.method;
			captureForThread.contentType = request.contentType;
			captureForThread.body = request.body;
			client.output.writeString("HTTP/1.1 200 OK\r\nContent-Length: "
				+ responseBody.length
				+ "\r\nSet-Cookie: a=1\r\nSet-Cookie: b=2\r\nConnection: close\r\n\r\n"
				+ responseBody);
			client.close();
			server.close();
			doneForThread.release();
		});

		final built = build(port);
		var responseData = "";
		built.http.onData = function(data) responseData = data;
		built.http.onError = function(msg) throw msg;
		built.run();
		done.wait();

		return {
			http: built.http,
			capture: capture,
			responseData: responseData
		};
	}

	static function readRequest(client:Socket):CapturedRequest {
		final requestLine = client.input.readLine();
		final requestParts = requestLine.split(" ");
		final method = requestParts[0];
		var contentLength = 0;
		var contentType:Null<String> = null;

		while (true) {
			final line = client.input.readLine();
			if (line == "")
				break;
			final sep = line.indexOf(":", 0);
			if (sep < 0)
				continue;
			final name = line.substr(0, sep);
			final value = StringTools.trim(line.substr(sep + 1));
			switch (name.toLowerCase()) {
				case "content-length":
					contentLength = parseDecimalInt(value);
				case "content-type":
					contentType = value;
				default:
			}
		}

		var body = "";
		if (contentLength > 0) {
			final bytes = Bytes.alloc(contentLength);
			client.input.readFullBytes(bytes, 0, contentLength);
			body = bytes.toString();
		}

		return {
			method: method,
			contentType: contentType,
			body: body
		};
	}

	static function joinHeaderValues(values:Null<Array<String>>):String {
		return values == null ? "null" : values.join("|");
	}

	static function stringifyNull(value:Null<String>):String {
		return value == null ? "null" : value;
	}

	static function extractBoundary(contentType:Null<String>):Null<String> {
		if (contentType == null)
			return null;
		final marker = "boundary=";
		final boundaryIndex = contentType.indexOf(marker, 0);
		if (boundaryIndex < 0)
			return null;
		return contentType.substr(boundaryIndex + marker.length);
	}

	static function parseDecimalInt(text:String):Int {
		var value = 0;
		for (i in 0...text.length) {
			final digit = text.substr(i, 1);
			final numeric = switch (digit) {
				case "0": 0;
				case "1": 1;
				case "2": 2;
				case "3": 3;
				case "4": 4;
				case "5": 5;
				case "6": 6;
				case "7": 7;
				case "8": 8;
				case "9": 9;
				default: return 0;
			};
			value = (value * 10) + numeric;
		}
		return value;
	}
}

private class StaticBytesInput extends haxe.io.Input {
	final bytes:Bytes;
	var position:Int = 0;

	public function new(bytes:Bytes) {
		this.bytes = bytes;
	}

	override public function readByte():Int {
		if (position >= bytes.length)
			throw new haxe.io.Eof();
		return bytes.get(position++);
	}

	override public function readBytes(buf:Bytes, pos:Int, len:Int):Int {
		if (position >= bytes.length)
			throw new haxe.io.Eof();
		final available = bytes.length - position;
		final count = available < len ? available : len;
		buf.blit(pos, bytes, position, count);
		position += count;
		return count;
	}
}
