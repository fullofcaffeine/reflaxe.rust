class Main {
	static function forward(channel:IChannel):ChannelOwner {
		return new ChannelOwner(channel);
	}

	static function main() {
		var channel:IChannel = new Channel();
		Sys.println(forward(channel).label());
	}
}
