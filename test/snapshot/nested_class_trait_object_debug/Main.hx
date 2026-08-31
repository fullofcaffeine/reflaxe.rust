interface LabelSource {
	public function label():String;
}

class FixedLabelSource implements LabelSource {
	final value:String;

	public function new(value:String) {
		this.value = value;
	}

	public function label():String {
		return value;
	}
}

class LabelProvider {
	public final source:LabelSource;

	public function new(source:LabelSource) {
		this.source = source;
	}

	public function label():String {
		return source.label();
	}
}

class LabelOwner {
	public final provider:LabelProvider;

	public function new(provider:LabelProvider) {
		this.provider = provider;
	}

	public function label():String {
		return provider.label();
	}
}

typedef LabelProviderList = Array<LabelProvider>;

abstract LabelProviderGroup(LabelProviderList) from LabelProviderList to LabelProviderList {
	@:arrayAccess
	public inline function get(index:Int):LabelProvider {
		return this[index];
	}
}

class LabelGroupOwner {
	public final providers:LabelProviderGroup;

	public function new(providers:LabelProviderGroup) {
		this.providers = providers;
	}

	public function label():String {
		return providers[0].label();
	}
}

class ErasedTypeOwner {
	public final kind:Class<LabelProvider>;

	public function new(kind:Class<LabelProvider>) {
		this.kind = kind;
	}
}

class DebugLeaf {
	public final value:Int;

	public function new(value:Int) {
		this.value = value;
	}
}

class DebugOwner {
	public final leaf:DebugLeaf;

	public function new(leaf:DebugLeaf) {
		this.leaf = leaf;
	}
}

class DebugNode {
	public final next:Null<DebugNode>;

	public function new(next:Null<DebugNode>) {
		this.next = next;
	}
}

class Main {
	static function main():Void {
		final source:LabelSource = new FixedLabelSource("ready");
		final owner = new LabelOwner(new LabelProvider(source));
		final groupOwner = new LabelGroupOwner([new LabelProvider(source)]);
		final erasedTypeOwner = new ErasedTypeOwner(LabelProvider);
		final debugOwner = new DebugOwner(new DebugLeaf(1));
		final debugNode = new DebugNode(null);
		if (owner.label() != "ready"
			|| groupOwner.label() != "ready"
			|| erasedTypeOwner.kind != LabelProvider
			|| debugOwner.leaf.value != 1
			|| debugNode.next != null) {
			throw "unexpected label";
		}
	}
}
