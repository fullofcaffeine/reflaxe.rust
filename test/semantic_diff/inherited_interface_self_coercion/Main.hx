private interface Session {
	public function value():String;
	public function callTransport():String;
}

private interface SessionTransport {
	public function deliver(session:Session):String;
}

private class EchoTransport implements SessionTransport {
	public function new() {}

	public function deliver(session:Session):String {
		return "deliver:" + session.value();
	}
}

private class BaseSession implements Session {
	final transport:SessionTransport;

	public function new(transport:SessionTransport) {
		this.transport = transport;
	}

	public function value():String {
		return privateLabel();
	}

	public function callTransport():String {
		return transport.deliver(this);
	}

	static function privateLabel():String {
		return "base";
	}
}

private class ChildSession extends BaseSession {
	public function new(transport:SessionTransport) {
		super(transport);
	}
}

class Main {
	static function main():Void {
		final session:Session = new ChildSession(new EchoTransport());
		if (session.value() != "base")
			throw "inherited value mismatch";
		if (session.callTransport() != "deliver:base")
			throw "inherited interface transport mismatch";
	}
}
