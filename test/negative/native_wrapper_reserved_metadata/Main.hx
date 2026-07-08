@:native("crate::native_wrapper_probe::Probe")
@:rustNativeWrapper({
	module: "native_wrapper_probe",
	name: "Probe",
	inner: "std::net::SocketAddr",
	field: "addr",
	derives: ["Clone", "Copy", "Debug"],
	conversions: {
		from: "from_std",
		as: "as_std",
		visibility: "pub(crate)"
	}
})
extern class Probe {}

class Main {
	static function main():Void {
		Sys.println("native-wrapper-reserved");
	}
}
