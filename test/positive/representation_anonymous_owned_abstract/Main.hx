private abstract UserId(Int) from Int to Int {}

private enum OwnedCarrier<T> {
	Empty;
}

private abstract Deep<T>(Array<Array<T>>) from Array<Array<T>> to Array<Array<T>> {}
private typedef D1<T> = Deep<T>;
private typedef D2<T> = Deep<D1<T>>;
private typedef D3<T> = Deep<D2<T>>;
private typedef D4<T> = Deep<D3<T>>;
private typedef D5<T> = Deep<D4<T>>;
private typedef D6<T> = Deep<D5<T>>;

private typedef OwnedNode = {
	@:optional var next:OwnedNode;
}

private typedef UserRecord = {
	@:optional var userId:UserId;
	@:optional var userIds:Array<UserId>;
	@:optional var buildUserId:Void->UserId;
	@:optional var acceptUserId:UserId->Void;
	@:optional var retained:OwnedCarrier<UserId>;
}

@:forward(userId)
private abstract OwnedRecord(UserRecord) from UserRecord to UserRecord {}

class Main {
	static function box<T>(value:T):Deep<T> {
		return [[value]];
	}

	static function main():Void {
		var record:UserRecord = {};
		var wrapped:OwnedRecord = {};
		if (record.userId != null) {
			trace(record.userId);
		}
		if (wrapped.userId != null) {
			trace(wrapped.userId);
		}

		var deep:D6<Int> = box(box(box(box(box(box(7))))));
		var node:OwnedNode = {};
		var number = 7;
		var safeNode = rust.Borrow.withRef(number, _borrowed -> node);
		if (deep == null || safeNode == null) {}
	}
}
