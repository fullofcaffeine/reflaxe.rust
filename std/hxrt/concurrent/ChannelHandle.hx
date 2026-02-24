package hxrt.concurrent;

/**
	Opaque runtime channel handle (`hxrt::concurrent::ChannelHandle<T>`).

	Why
	- `rust.concurrent.Channel<T>` needs stable runtime storage for sender/receiver endpoints.
	- Keeping this as an opaque extern prevents lock/queue internals from leaking into user code.
**/
@:native("hxrt::concurrent::ChannelHandle")
extern class ChannelHandle<T> {}
