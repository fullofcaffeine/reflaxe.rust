enum GenericParse<T> {
	Parsed(value:T);
	Missing(reason:String);
}
