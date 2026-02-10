import sys.db.Sqlite;

class Main {
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

		var r1:Dynamic = rs.next();
		Sys.println("len1=" + rs.length + " row1=" + r1.id + "," + r1.name + "," + r1.done + " get0=" + rs.getIntResult(0));

		var r2:Dynamic = rs.next();
		Sys.println("len2=" + rs.length + " row2=" + r2.id + "," + r2.name + "," + r2.done + " get1=" + rs.getResult(1));

		var r3:Dynamic = rs.next();
		Sys.println("end=" + (r3 == null));
	}
}
