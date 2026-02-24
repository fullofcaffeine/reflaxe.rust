package rust.concurrent;

/**
	rust.concurrent.Channel<T>

	Why
	- Rusty-profile channel APIs need a concrete handle type that maps directly to runtime storage.

	What
	- Typedef alias to `hxrt.concurrent.ChannelHandle<T>`.
	- User-facing operations are exposed in `rust.concurrent.Channels`.

	How
	- Keeping the handle as a typedef avoids generating an extra wrapper class in Rust output.
**/
typedef Channel<T> = hxrt.concurrent.ChannelHandle<T>;
