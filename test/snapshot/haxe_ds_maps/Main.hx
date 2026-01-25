import haxe.ds.StringMap;
import haxe.ds.IntMap;
import haxe.ds.ObjectMap;
import haxe.ds.EnumValueMap;

class Key {
	public var id: Int;

	public function new(id: Int) {
		this.id = id;
	}

	public function toString(): String {
		return "Key(" + id + ")";
	}
}

enum E {
	A;
	B(v: Int);
}

class Main {
	static function main(): Void {
		trace("--- StringMap<Int> ---");
		var sm = new StringMap<Int>();
		sm.set("a", 1);
		sm.set("b", 2);
		trace(sm.exists("a"));
		trace(sm.exists("z"));
		trace(sm.get("a") == null);
		trace(sm.get("z") == null);
		for (k in sm.keys()) trace("k=" + k);
		for (v in sm.iterator()) trace("v=" + v);
		for (kv in sm.keyValueIterator()) trace(kv.key + "=>" + kv.value);
		trace(sm.remove("a"));
		trace(sm.exists("a"));
		var sm2 = sm.copy();
		trace(sm2.exists("b"));
		sm.clear();
		trace(sm.exists("b"));

		trace("--- IntMap<Int> ---");
		var im = new IntMap<Int>();
		im.set(10, 7);
		im.set(20, 9);
		trace(im.exists(10));
		trace(im.get(10) == null);
		trace(im.get(999) == null);
		for (k in im.keys()) trace("k=" + k);
		for (v in im.iterator()) trace("v=" + v);
		for (kv in im.keyValueIterator()) trace(kv.key + "=>" + kv.value);

		trace("--- ObjectMap<Key, Int> ---");
		var om = new ObjectMap<Key, Int>();
		var k1 = new Key(1);
		var k2 = new Key(2);
		om.set(k1, 100);
		om.set(k2, 200);
		trace(om.exists(k1));
		trace(om.get(k1) == null);
		trace(om.get(new Key(1)) == null); // identity: different instance, should not exist
		for (k in om.keys()) trace("k=" + k);
		for (v in om.iterator()) trace("v=" + v);
		for (kv in om.keyValueIterator()) trace(kv.key + "=>" + kv.value);

		trace("--- EnumValueMap<E, Int> ---");
		var em = new EnumValueMap<E, Int>();
		em.set(A, 1);
		em.set(B(3), 9);
		trace(em.exists(A));
		trace(em.get(A) == null);
		trace(em.get(B(999)) == null);
		for (k in em.keys()) trace("k=" + Std.string(k));
		for (v in em.iterator()) trace("v=" + v);
		for (kv in em.keyValueIterator()) trace(Std.string(kv.key) + "=>" + kv.value);
	}
}

