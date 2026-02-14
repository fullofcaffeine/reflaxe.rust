package profile;

/**
 * RuntimeFactory
 *
 * Why
 * - Compile variants should switch profile behavior without duplicating source trees.
 *
 * What
 * - Selects one `ChatRuntime` implementation using explicit example defines.
 *
 * How
 * - Each example `.hxml` sets exactly one of:
 *   `chat_profile_portable`, `chat_profile_idiomatic`, `chat_profile_rusty`, `chat_profile_metal`.
 */
class RuntimeFactory {
	public static function create():ChatRuntime {
		#if chat_profile_portable
		return new PortableRuntime();
		#elseif chat_profile_idiomatic
		return new IdiomaticRuntime();
		#elseif chat_profile_rusty
		return new RustyRuntime();
		#elseif chat_profile_metal
		return new MetalRuntime();
		#else
		#error "chat_loopback requires one chat_profile_* define."
		#end
	}
}
