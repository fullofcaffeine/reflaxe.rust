import rust.Borrow;

private enum RetainedCarrier<T> {
	Empty;
}

#if carrier_nested_array
private typedef DirectBorrowedValue = Array<rust.Ref<Int>>;
#elseif carrier_nested_function_argument
private typedef DirectBorrowedValue = rust.Ref<Int>->Void;
#elseif carrier_nested_function
private typedef DirectBorrowedValue = Void->rust.Ref<Int>;
#elseif carrier_nested_enum
private typedef DirectBorrowedValue = RetainedCarrier<rust.Slice<Int>>;
#elseif carrier_mut_ref
private typedef DirectBorrowedValue = rust.MutRef<Int>;
#elseif carrier_mut_slice
private typedef DirectBorrowedValue = rust.MutSlice<Int>;
#elseif carrier_slice
private typedef DirectBorrowedValue = rust.Slice<Int>;
#elseif carrier_str
private typedef DirectBorrowedValue = rust.Str;
#else
private typedef DirectBorrowedValue = rust.Ref<String>;
#end

#if abstract_wrapper
private abstract BorrowedAlias(DirectBorrowedValue) from DirectBorrowedValue to DirectBorrowedValue {}
#end

#if abstract_wrapper
#if nullable
private typedef BorrowedValue = Null<BorrowedAlias>;
#else
private typedef BorrowedValue = BorrowedAlias;
#end
#else
#if nullable
private typedef BorrowedValue = Null<DirectBorrowedValue>;
#else
private typedef BorrowedValue = DirectBorrowedValue;
#end
#end

#if optional
private typedef BorrowedHolderShape<T> = {
	@:optional var value:T;
}
#else
private typedef BorrowedHolderShape<T> = {
	var value:T;
}
#end

#if outer_record_null
private typedef BorrowedHolder = Null<BorrowedHolderShape<BorrowedValue>>;
#elseif outer_record_abstract
@:forward(value)
private abstract BorrowedHolderCarrier<T>(BorrowedHolderShape<T>) from BorrowedHolderShape<T> to BorrowedHolderShape<T> {}
private typedef BorrowedHolder = BorrowedHolderCarrier<BorrowedValue>;
#else
private typedef BorrowedHolder = BorrowedHolderShape<BorrowedValue>;
#end

class Main {
	#if operation_typed_read
	static function main():Void {
		var typedReadHolder:BorrowedHolder = {};
		var readBack = typedReadHolder.value;
		if (readBack == null) {}
	}
	#elseif operation_dynamic_control
	static function write(holder:BorrowedHolder, borrowed:rust.Ref<String>, flag:Bool):Void {
		var erased:Dynamic = flag ? holder : holder;
		Reflect.setField(erased, "value", borrowed);
	}

	static function main():Void {}
	#elseif (operation_runtime_reflect || operation_dynamic_reflect)
	static function main():Void {
		#if (outer_record_abstract || outer_record_null)
		var holder:BorrowedHolder = haxe.Json.parse("{}");
		#else
		var holder:BorrowedHolder = {};
		#end
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
