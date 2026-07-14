import reflaxe.rust.macros.RustInjection;
import rust.concurrent.Task;
import rust.concurrent.Tasks;

class Main {
	// Documentation may name `hxrt.sys.NativeSys` without becoming an application dependency.
	static final helperPathDocumentation = "hxrt.sys.NativeSys";
	static final helperPathPattern = ~/hxrt\.sys\.NativeSys/;

	static function preserveTask<T>(task:rust.HxRef<Task<T>>):rust.HxRef<Task<T>> {
		return task;
	}

	static function main():Void {
		var hxrt = 7;
		var buffer = new StringBuf();
		buffer.add("public facade");
		buffer.add(hxrt);
		buffer.add(helperPathDocumentation);
		buffer.add(helperPathPattern.match("hxrt.sys.NativeSys"));
		Sys.println(buffer.toString());

		var task = Tasks.spawn(() -> 42);
		Sys.println(Tasks.join(preserveTask(task)));
	}
}
