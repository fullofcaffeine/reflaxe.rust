typedef Item = {
	var modelId:String;
	var rank:Int;
}

class Main {
	static function main() {
		var items:Array<Item> = [{modelId: "b", rank: 2}, {modelId: "a", rank: 3}, {modelId: "a", rank: 1}];

		items.sort((left, right) -> {
			var byModel = Reflect.compare(left.modelId, right.modelId);
			return if (byModel != 0) byModel else Reflect.compare(left.rank, right.rank);
		});

		for (item in items) {
			Sys.println(item.modelId + ":" + item.rank);
		}
	}
}
