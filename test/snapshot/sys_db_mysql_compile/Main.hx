import sys.db.Mysql;

class Main {
	static function main() {
		// Compile-only snapshot: we want to ensure `sys.db.Mysql` codegen + Cargo deps compile.
		// The snapshot harness does not execute binaries unless `intended/stdout.txt` exists.
		if (Sys.args().length < 0) {
			Mysql.connect({
				host: "127.0.0.1",
				user: "root",
				pass: "",
				database: null
			});
		}
		Sys.println("ok");
	}
}

