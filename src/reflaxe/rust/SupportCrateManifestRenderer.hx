package reflaxe.rust;

#if macro
import haxe.io.Bytes;
import reflaxe.rust.SupportCrateRequestPlan.SupportCrateRequest;

/** Renders the only Cargo manifest bytes accepted for one support crate. */
final class SupportCrateManifestRenderer {
	public static function render(request:SupportCrateRequest):Bytes {
		var output = new StringBuf();
		output.add('[package]\n');
		output.add('name = "${request.name}"\n');
		output.add('version = "0.0.0"\n');
		output.add('edition = "2021"\n');
		output.add('publish = false\n\n');
		output.add('[lib]\n');
		output.add('path = "src/lib.rs"\n\n');
		output.add('[dependencies]\n');
		for (dependency in request.dependencies()) {
			output.add(dependency.name);
			output.add(' = { version = "');
			output.add(dependency.version);
			output.add('", default-features = ');
			output.add(dependency.defaultFeatures ? 'true' : 'false');
			output.add(', features = [');
			var features = dependency.features();
			for (index in 0...features.length) {
				if (index > 0)
					output.add(', ');
				output.add('"');
				output.add(features[index]);
				output.add('"');
			}
			output.add('] }\n');
		}
		return Bytes.ofString(output.toString());
	}
}
#end
