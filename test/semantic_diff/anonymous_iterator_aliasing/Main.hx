private typedef Cursor = {
	var hasNext:Void->Bool;
	var next:Void->Int;
}

class Main {
	static var active:Cursor;

	static function makeCursor():Cursor {
		var value = 1;
		return {
			hasNext: function():Bool {
				return value <= 2;
			},
			next: function():Int {
				return value++;
			}
		};
	}

	static function makeSelfMutatingCursor():Cursor {
		var cursor:Cursor = {
			hasNext: function():Bool {
				active.next = function():Int {
					return 7;
				};
				return false;
			},
			next: function():Int {
				return 1;
			}
		};
		active = cursor;
		return cursor;
	}

	static function main() {
		var cursor = makeCursor();
		var alias = cursor;

		Sys.println("first=" + alias.next());
		alias.next = function():Int {
			return 99;
		};

		Sys.println("sharedNext=" + cursor.next());
		Sys.println("hasNext=" + cursor.hasNext());
		Sys.println("same=" + (cursor == alias));

		var loopCursor = makeCursor();
		var values = [];
		for (value in loopCursor) {
			values.push(value);
		}
		Sys.println("for=" + values.join(","));

		var selfMutating = makeSelfMutatingCursor();
		Sys.println("selfHasNext=" + selfMutating.hasNext());
		Sys.println("selfNext=" + selfMutating.next());
	}
}
