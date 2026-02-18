package profile;

/**
	Selects the runtime implementation from compile-time defines.
**/
class RuntimeFactory {
	public static function create():StoryboardRuntime {
		#if storyboard_profile_portable
		return new PortableRuntime();
		#elseif storyboard_profile_idiomatic
		return new IdiomaticRuntime();
		#elseif storyboard_profile_rusty
		return new RustyRuntime();
		#elseif storyboard_profile_metal
		return new MetalRuntime();
		#else
		return new PortableRuntime();
		#end
	}
}
