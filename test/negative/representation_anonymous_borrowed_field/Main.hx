import rust.Borrow;

#if nullable
private typedef BorrowedValue = Null<rust.Ref<String>>;
#else
private typedef BorrowedValue = rust.Ref<String>;
#end

#if optional
private typedef BorrowedHolder = {
	@:optional var value:BorrowedValue;
}
#else
private typedef BorrowedHolder = {
	var value:BorrowedValue;
}
#end

class Main {
	#if operation_dynamic_control
	static function write(holder:BorrowedHolder, borrowed:rust.Ref<String>, flag:Bool):Void {
		var erased:Dynamic = flag ? holder : holder;
		Reflect.setField(erased, "value", borrowed);
	}

	static function main():Void {}
	#elseif (operation_runtime_reflect || operation_dynamic_reflect)
	static function main():Void {
		var holder:BorrowedHolder = {};
		var fieldName = "value";
		var label = "temporary";
		Borrow.withRef(label, borrowed -> {
			#if operation_runtime_reflect
			Reflect.setField(holder, fieldName, borrowed);
			#else
			var erased:Dynamic = holder;
			Reflect.setField(erased, "value", borrowed);
			#end
			var readBack = holder.value;
			if (readBack == null) {}
		});
	}
	#elseif operation_literal
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
