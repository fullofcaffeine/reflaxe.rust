package sys.net;

import haxe.io.Bytes;
import hxrt.net.NativeSocket;
import hxrt.net.SocketHandle;
import rust.HxRef;
import sys.net._SocketIO.SocketInput;
import sys.net._SocketIO.SocketOutput;
import sys.net.Types.SocketCustomValue;

/**
	`sys.net.Socket` (Rust target implementation)

	Why
	- The upstream stdlib declares `sys.net.Socket` as `extern`, so sys targets must provide a real
	  TCP socket implementation.

	What
	- Implements basic TCP networking:
	  - `connect`, `bind`, `listen`, `accept`
	  - `peer`, `host`
	  - `setTimeout`, `setBlocking`, `setFastSend`, `shutdown`
	  - `select` (best-effort readiness polling)

	How
	- Socket state lives in the Rust runtime (`hxrt::net::SocketHandle`) and is referenced from Haxe
	  via `HxRef<SocketHandle>`.
	- `input`/`output` are exposed as properties to avoid storing Rust trait objects inside the
	  generated struct (this keeps generated Rust simpler and warning-free).
	- Rust-native operations are called through the typed `hxrt.net.NativeSocket` boundary so this
	  std module does not rely on raw `__rust__` injection.
**/
class Socket {
	public var input(default, null):haxe.io.Input;
	public var output(default, null):haxe.io.Output;

	/**
		A custom value that can be associated with the socket.

		Note: this remains a boundary-typed payload (`SocketCustomValue`) to match
		upstream `sys.net.Socket` behavior while documenting intentional untyped storage.
	**/
	public var custom:Null<SocketCustomValue> = null;

	@:allow(sys.net.UdpSocket)
	@:allow(sys.ssl.Socket)
	private var handle:HxRef<SocketHandle>;

	public function new():Void {
		var h:HxRef<SocketHandle> = NativeSocket.newTcp();
		handle = h;
		input = new SocketInput(h);
		output = new SocketOutput(h);
	}

	public function close():Void {
		NativeSocket.closeHandle(handle);
	}

	public function read():String {
		return input.readAll().toString();
	}

	public function write(content:String):Void {
		output.writeString(content);
	}

	public function connect(host:Host, port:Int):Void {
		NativeSocket.connect(handle, host.ip, port);
	}

	public function listen(connections:Int):Void {
		NativeSocket.listen(handle, connections);
	}

	public function shutdown(read:Bool, write:Bool):Void {
		NativeSocket.shutdown(handle, read, write);
	}

	public function bind(host:Host, port:Int):Void {
		NativeSocket.bind(handle, host.ip, port);
	}

	public function accept():Socket {
		var h:HxRef<SocketHandle> = NativeSocket.accept(handle);
		var s:Socket = new Socket();
		s.handle = h;
		s.input = new SocketInput(h);
		s.output = new SocketOutput(h);
		return s;
	}

	public function peer():{host:Host, port:Int} {
		var host:Host = new Host("127.0.0.1");
		untyped host.ip = NativeSocket.peerIp(handle);
		return {host: host, port: NativeSocket.peerPort(handle)};
	}

	public function host():{host:Host, port:Int} {
		var host:Host = new Host("127.0.0.1");
		untyped host.ip = NativeSocket.hostIp(handle);
		return {host: host, port: NativeSocket.hostPort(handle)};
	}

	public function setTimeout(timeout:Float):Void {
		NativeSocket.setTimeout(handle, timeout);
	}

	public function waitForRead():Void {
		NativeSocket.waitForRead(handle);
	}

	public function setBlocking(b:Bool):Void {
		NativeSocket.setBlocking(handle, b);
	}

	public function setFastSend(b:Bool):Void {
		NativeSocket.setFastSend(handle, b);
	}

	public static function select(read:Array<Socket>, write:Array<Socket>, others:Array<Socket>,
			?timeout:Float):{read:Array<Socket>, write:Array<Socket>, others:Array<Socket>} {
		var rh:Array<HxRef<SocketHandle>> = [for (s in read) s.handle];
		var wh:Array<HxRef<SocketHandle>> = [for (s in write) s.handle];
		var oh:Array<HxRef<SocketHandle>> = [for (s in others) s.handle];
		var idxGroups:Array<Array<Int>> = NativeSocket.selectGroups(rh, wh, oh, timeout);

		function pick(src:Array<Socket>, idx:Array<Int>):Array<Socket> {
			var out:Array<Socket> = [];
			for (i in idx)
				out.push(src[i]);
			return out;
		}

		return {
			read: pick(read, idxGroups[0]),
			write: pick(write, idxGroups[1]),
			others: pick(others, idxGroups[2]),
		};
	}
}
