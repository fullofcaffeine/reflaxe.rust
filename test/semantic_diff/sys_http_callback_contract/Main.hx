import haxe.io.Bytes;
import sys.Http;
import sys.net.Host;
import sys.net.Socket;
import sys.thread.Lock;
import sys.thread.Thread;

private typedef HttpResponse = {
	var status:Int;
	var body:String;
}

class Main {
	static function main() {
		final success = runSuccessCase();
		Sys.println('status=' + success.status);
		Sys.println('body=' + success.body);

		final errorHandled = runErrorCase();
		Sys.println('error_handled=' + errorHandled);
	}

	static function runSuccessCase():HttpResponse {
		final server = new Socket();
		server.bind(new Host("127.0.0.1"), 0);
		server.listen(1);

		final port = server.host().port;
		final done = new Lock();
		final doneForThread = done;

		Thread.create(() -> {
			final client = server.accept();
			drainRequest(client);
			client.output.writeString("HTTP/1.1 201 Created\r\n" + "Content-Length: 2\r\n" + "Connection: close\r\n\r\n" + "ok");
			client.close();
			server.close();
			doneForThread.release();
		});

		final http = new Http("http://127.0.0.1:" + port + "/status");
		var status = -1;
		var body = "";
		http.onStatus = function(code) status = code;
		http.onData = function(data) body = data;
		http.onError = function(msg) throw msg;
		http.request(false);
		done.wait();

		return {
			status: status,
			body: body
		};
	}

	static function runErrorCase():Bool {
		final listener = new Socket();
		listener.bind(new Host("127.0.0.1"), 0);
		final port = listener.host().port;
		listener.close();

		final http = new Http("http://127.0.0.1:" + port + "/closed");
		var handled = false;
		http.onData = function(_) handled = false;
		http.onError = function(_) handled = true;
		http.request(false);
		return handled;
	}

	static function drainRequest(client:Socket):Void {
		while (true) {
			final line = client.input.readLine();
			if (line == "")
				break;
		}
	}
}
