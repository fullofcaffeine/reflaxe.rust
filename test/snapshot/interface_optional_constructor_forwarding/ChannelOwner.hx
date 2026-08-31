class ChannelOwner {
	final channel:Null<IChannel>;

	public function new(?channel:IChannel) {
		this.channel = channel;
	}

	public function label():String {
		return channel == null ? "missing" : channel.label();
	}
}
