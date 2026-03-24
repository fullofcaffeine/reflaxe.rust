import sys.db.Sqlite;

private typedef TodoRow = {
	var id:Int;
	var name:String;
	var done:Int;
};

class Main {
	/**
		Why
		- `sys.db.ResultSet.next()` is an intentionally untyped boundary in upstream Haxe APIs.
		- The Rust target returns a dynamic row object at that boundary, so direct `cast` to a typed
		  anonymous structure is the wrong contract to test.

		What
		- Decodes one DB row into the typed `TodoRow` structure used by this smoke fixture.

		How
		- Reads fields through `Reflect.field(...)` at the boundary.
		- Immediately validates them with `Std.isOfType(...)` and returns to strongly typed code.
	**/
	static function decodeTodo(row:Dynamic):TodoRow {
		var id:Dynamic = Reflect.field(row, "id");
		var name:Dynamic = Reflect.field(row, "name");
		var done:Dynamic = Reflect.field(row, "done");

		if (!Std.isOfType(id, Int) || !Std.isOfType(name, String) || !Std.isOfType(done, Int)) {
			throw "invalid sqlite todo row";
		}

		return {
			id: cast id,
			name: Std.string(name),
			done: cast done
		};
	}

	static function main() {
		var cnx = Sqlite.open(":memory:");
		cnx.request("CREATE TABLE todo (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, done INTEGER NOT NULL)");

		cnx.request("INSERT INTO todo (name, done) VALUES (" + cnx.quote("bootstrap reflaxe.rust") + ", 1)");
		cnx.request("INSERT INTO todo (name, done) VALUES (" + cnx.quote("ship sys.db sqlite") + ", 0)");

		var rs = cnx.request("SELECT id, name, done FROM todo ORDER BY id");

		var fields = rs.getFieldsNames();
		Sys.println("db=" + cnx.dbName());
		Sys.println("fields=" + (fields == null ? "null" : (cast fields : Array<String>).join(",")));
		Sys.println("len0=" + rs.length + " nf=" + rs.nfields);

		var r1 = decodeTodo(rs.next());
		Sys.println("len1=" + rs.length + " row1=" + r1.id + "," + r1.name + "," + r1.done + " get0=" + rs.getIntResult(0));

		var r2 = decodeTodo(rs.next());
		Sys.println("len2=" + rs.length + " row2=" + r2.id + "," + r2.name + "," + r2.done + " get1=" + rs.getResult(1));

		var r3 = rs.next();
		Sys.println("end=" + (r3 == null));
	}
}
