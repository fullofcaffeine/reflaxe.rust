private abstract UserId(Int) from Int to Int {}

private typedef UserRecord = {
	@:optional var userId:UserId;
}

class Main {
	static function main():Void {
		var record:UserRecord = {};
		if (record.userId != null) {
			trace(record.userId);
		}
	}
}
