import rust.Borrow;

#if nullable
private typedef BorrowedValue = Null<rust.Ref<String>>;
#else
private typedef BorrowedValue = rust.Ref<String>;
#end

private typedef BorrowedHolder = {
	var value:BorrowedValue;
}

class Main {
	#if operation_literal
	static function main():Void {
		var label = "temporary";
		Borrow.withRef(label, borrowed -> {
			var holder:BorrowedHolder = {value: borrowed};
			if (holder == null) {}
		});
	}
	#else
	static function write(holder:BorrowedHolder):Void {
		#if operation_assign
		holder.value = (cast null : BorrowedValue);
		#elseif operation_reflect
		Reflect.setField(holder, "value", (cast null : BorrowedValue));
		#end
		return;
	}

	static function main():Void {}
	#end
}
