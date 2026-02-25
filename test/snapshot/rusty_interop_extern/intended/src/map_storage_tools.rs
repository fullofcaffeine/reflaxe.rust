/// `map_storage_tools` (metal string profile)
///
/// Typed helper module backing `rust.MapStorageTools` when `String` lowers to Rust `String`.
#[derive(Debug)]
pub struct MapStorageTools;

#[allow(non_snake_case)]
impl MapStorageTools {
    pub fn stringMapSet<V: Clone + Send + Sync + 'static + std::fmt::Debug>(
        map: crate::HxRef<crate::haxe_ds_string_map::StringMap<V>>,
        key: String,
        value: V,
    ) {
        map.borrow_mut().h.insert(key, value);
    }

    pub fn stringMapGetCloned<V: Clone + Send + Sync + 'static + std::fmt::Debug>(
        map: crate::HxRef<crate::haxe_ds_string_map::StringMap<V>>,
        key: String,
    ) -> Option<V> {
        map.borrow().h.get(&key).cloned()
    }

    pub fn stringMapExists<V: Clone + Send + Sync + 'static + std::fmt::Debug>(
        map: crate::HxRef<crate::haxe_ds_string_map::StringMap<V>>,
        key: String,
    ) -> bool {
        map.borrow().h.contains_key(&key)
    }

    pub fn stringMapRemoveExists<V: Clone + Send + Sync + 'static + std::fmt::Debug>(
        map: crate::HxRef<crate::haxe_ds_string_map::StringMap<V>>,
        key: String,
    ) -> bool {
        map.borrow_mut().h.remove(&key).is_some()
    }

    pub fn stringMapKeysOwned<V: Clone + Send + Sync + 'static + std::fmt::Debug>(
        map: crate::HxRef<crate::haxe_ds_string_map::StringMap<V>>,
    ) -> hxrt::iter::Iter<String> {
        hxrt::iter::Iter::from_vec(map.borrow().h.keys().cloned().collect::<Vec<_>>())
    }

    pub fn stringMapValuesOwned<V: Clone + Send + Sync + 'static + std::fmt::Debug>(
        map: crate::HxRef<crate::haxe_ds_string_map::StringMap<V>>,
    ) -> hxrt::iter::Iter<V> {
        hxrt::iter::Iter::from_vec(map.borrow().h.values().cloned().collect::<Vec<_>>())
    }

    pub fn stringMapKeyValuesOwned<V: Clone + Send + Sync + 'static + std::fmt::Debug>(
        map: crate::HxRef<crate::haxe_ds_string_map::StringMap<V>>,
    ) -> hxrt::iter::Iter<hxrt::iter::KeyValue<String, V>> {
        hxrt::iter::Iter::from_vec(
            map.borrow()
                .h
                .iter()
                .map(|(k, v)| hxrt::iter::KeyValue {
                    key: k.clone(),
                    value: v.clone(),
                })
                .collect::<Vec<_>>(),
        )
    }

    pub fn stringMapCloneInto<V: Clone + Send + Sync + 'static + std::fmt::Debug>(
        dst: crate::HxRef<crate::haxe_ds_string_map::StringMap<V>>,
        src: crate::HxRef<crate::haxe_ds_string_map::StringMap<V>>,
    ) {
        dst.borrow_mut().h = src.borrow().h.clone();
    }

    pub fn stringMapDebugString<V: Clone + Send + Sync + 'static + std::fmt::Debug>(
        map: crate::HxRef<crate::haxe_ds_string_map::StringMap<V>>,
    ) -> String {
        format!("{:?}", map.borrow().h)
    }

    pub fn stringMapClear<V: Clone + Send + Sync + 'static + std::fmt::Debug>(
        map: crate::HxRef<crate::haxe_ds_string_map::StringMap<V>>,
    ) {
        map.borrow_mut().h.clear();
    }

    pub fn intMapSet<V: Clone + Send + Sync + 'static + std::fmt::Debug>(
        map: crate::HxRef<crate::haxe_ds_int_map::IntMap<V>>,
        key: i32,
        value: V,
    ) {
        map.borrow_mut().h.insert(key, value);
    }

    pub fn intMapGetCloned<V: Clone + Send + Sync + 'static + std::fmt::Debug>(
        map: crate::HxRef<crate::haxe_ds_int_map::IntMap<V>>,
        key: i32,
    ) -> Option<V> {
        map.borrow().h.get(&key).cloned()
    }

    pub fn intMapExists<V: Clone + Send + Sync + 'static + std::fmt::Debug>(
        map: crate::HxRef<crate::haxe_ds_int_map::IntMap<V>>,
        key: i32,
    ) -> bool {
        map.borrow().h.contains_key(&key)
    }

    pub fn intMapRemoveExists<V: Clone + Send + Sync + 'static + std::fmt::Debug>(
        map: crate::HxRef<crate::haxe_ds_int_map::IntMap<V>>,
        key: i32,
    ) -> bool {
        map.borrow_mut().h.remove(&key).is_some()
    }

    pub fn intMapKeysOwned<V: Clone + Send + Sync + 'static + std::fmt::Debug>(
        map: crate::HxRef<crate::haxe_ds_int_map::IntMap<V>>,
    ) -> hxrt::iter::Iter<i32> {
        hxrt::iter::Iter::from_vec(map.borrow().h.keys().cloned().collect::<Vec<_>>())
    }

    pub fn intMapValuesOwned<V: Clone + Send + Sync + 'static + std::fmt::Debug>(
        map: crate::HxRef<crate::haxe_ds_int_map::IntMap<V>>,
    ) -> hxrt::iter::Iter<V> {
        hxrt::iter::Iter::from_vec(map.borrow().h.values().cloned().collect::<Vec<_>>())
    }

    pub fn intMapKeyValuesOwned<V: Clone + Send + Sync + 'static + std::fmt::Debug>(
        map: crate::HxRef<crate::haxe_ds_int_map::IntMap<V>>,
    ) -> hxrt::iter::Iter<hxrt::iter::KeyValue<i32, V>> {
        hxrt::iter::Iter::from_vec(
            map.borrow()
                .h
                .iter()
                .map(|(k, v)| hxrt::iter::KeyValue {
                    key: k.clone(),
                    value: v.clone(),
                })
                .collect::<Vec<_>>(),
        )
    }

    pub fn intMapCloneInto<V: Clone + Send + Sync + 'static + std::fmt::Debug>(
        dst: crate::HxRef<crate::haxe_ds_int_map::IntMap<V>>,
        src: crate::HxRef<crate::haxe_ds_int_map::IntMap<V>>,
    ) {
        dst.borrow_mut().h = src.borrow().h.clone();
    }

    pub fn intMapDebugString<V: Clone + Send + Sync + 'static + std::fmt::Debug>(
        map: crate::HxRef<crate::haxe_ds_int_map::IntMap<V>>,
    ) -> String {
        format!("{:?}", map.borrow().h)
    }

    pub fn intMapClear<V: Clone + Send + Sync + 'static + std::fmt::Debug>(
        map: crate::HxRef<crate::haxe_ds_int_map::IntMap<V>>,
    ) {
        map.borrow_mut().h.clear();
    }

    pub fn objectMapKeyId<
        K: hxrt::hxref::HxRefLike + Clone + Send + Sync + 'static + std::fmt::Debug,
    >(
        key: K,
    ) -> String {
        hxrt::hxref::ptr_id(&key)
    }

    pub fn objectMapSet<
        K: hxrt::hxref::HxRefLike + Clone + Send + Sync + 'static + std::fmt::Debug,
        V: Clone + Send + Sync + 'static + std::fmt::Debug,
    >(
        map: crate::HxRef<crate::haxe_ds_object_map::ObjectMap<K, V>>,
        id: String,
        key: K,
        value: V,
    ) {
        let mut storage = map.borrow_mut();
        storage.keys_map.insert(id.clone(), key);
        storage.values_map.insert(id, value);
    }

    pub fn objectMapGetCloned<
        K: hxrt::hxref::HxRefLike + Clone + Send + Sync + 'static + std::fmt::Debug,
        V: Clone + Send + Sync + 'static + std::fmt::Debug,
    >(
        map: crate::HxRef<crate::haxe_ds_object_map::ObjectMap<K, V>>,
        id: String,
    ) -> Option<V> {
        map.borrow().values_map.get(&id).cloned()
    }

    pub fn objectMapExists<
        K: hxrt::hxref::HxRefLike + Clone + Send + Sync + 'static + std::fmt::Debug,
        V: Clone + Send + Sync + 'static + std::fmt::Debug,
    >(
        map: crate::HxRef<crate::haxe_ds_object_map::ObjectMap<K, V>>,
        id: String,
    ) -> bool {
        map.borrow().values_map.contains_key(&id)
    }

    pub fn objectMapRemoveExists<
        K: hxrt::hxref::HxRefLike + Clone + Send + Sync + 'static + std::fmt::Debug,
        V: Clone + Send + Sync + 'static + std::fmt::Debug,
    >(
        map: crate::HxRef<crate::haxe_ds_object_map::ObjectMap<K, V>>,
        id: String,
    ) -> bool {
        let mut storage = map.borrow_mut();
        let existed = storage.values_map.remove(&id).is_some();
        storage.keys_map.remove(&id);
        existed
    }

    pub fn objectMapKeysOwned<
        K: hxrt::hxref::HxRefLike + Clone + Send + Sync + 'static + std::fmt::Debug,
        V: Clone + Send + Sync + 'static + std::fmt::Debug,
    >(
        map: crate::HxRef<crate::haxe_ds_object_map::ObjectMap<K, V>>,
    ) -> hxrt::iter::Iter<K> {
        hxrt::iter::Iter::from_vec(map.borrow().keys_map.values().cloned().collect::<Vec<_>>())
    }

    pub fn objectMapValuesOwned<
        K: hxrt::hxref::HxRefLike + Clone + Send + Sync + 'static + std::fmt::Debug,
        V: Clone + Send + Sync + 'static + std::fmt::Debug,
    >(
        map: crate::HxRef<crate::haxe_ds_object_map::ObjectMap<K, V>>,
    ) -> hxrt::iter::Iter<V> {
        hxrt::iter::Iter::from_vec(
            map.borrow()
                .values_map
                .values()
                .cloned()
                .collect::<Vec<_>>(),
        )
    }

    pub fn objectMapKeyValuesOwned<
        K: hxrt::hxref::HxRefLike + Clone + Send + Sync + 'static + std::fmt::Debug,
        V: Clone + Send + Sync + 'static + std::fmt::Debug,
    >(
        map: crate::HxRef<crate::haxe_ds_object_map::ObjectMap<K, V>>,
    ) -> hxrt::iter::Iter<hxrt::iter::KeyValue<K, V>> {
        hxrt::iter::Iter::from_vec({
            let storage = map.borrow();
            storage
                .values_map
                .iter()
                .map(|(id, value)| hxrt::iter::KeyValue {
                    key: storage.keys_map.get(id).unwrap().clone(),
                    value: value.clone(),
                })
                .collect::<Vec<_>>()
        })
    }

    pub fn objectMapCloneInto<
        K: hxrt::hxref::HxRefLike + Clone + Send + Sync + 'static + std::fmt::Debug,
        V: Clone + Send + Sync + 'static + std::fmt::Debug,
    >(
        dst: crate::HxRef<crate::haxe_ds_object_map::ObjectMap<K, V>>,
        src: crate::HxRef<crate::haxe_ds_object_map::ObjectMap<K, V>>,
    ) {
        let source = src.borrow();
        let mut out = dst.borrow_mut();
        out.keys_map = source.keys_map.clone();
        out.values_map = source.values_map.clone();
    }

    pub fn objectMapDebugString<
        K: hxrt::hxref::HxRefLike + Clone + Send + Sync + 'static + std::fmt::Debug,
        V: Clone + Send + Sync + 'static + std::fmt::Debug,
    >(
        map: crate::HxRef<crate::haxe_ds_object_map::ObjectMap<K, V>>,
    ) -> String {
        format!("{:?}", map.borrow().values_map)
    }

    pub fn objectMapClear<
        K: hxrt::hxref::HxRefLike + Clone + Send + Sync + 'static + std::fmt::Debug,
        V: Clone + Send + Sync + 'static + std::fmt::Debug,
    >(
        map: crate::HxRef<crate::haxe_ds_object_map::ObjectMap<K, V>>,
    ) {
        let mut storage = map.borrow_mut();
        storage.keys_map.clear();
        storage.values_map.clear();
    }

    pub fn enumValueMapSet<
        K: Clone + Send + Sync + 'static + std::fmt::Debug,
        V: Clone + Send + Sync + 'static + std::fmt::Debug,
    >(
        map: crate::HxRef<crate::haxe_ds_enum_value_map::EnumValueMap<K, V>>,
        id: String,
        key: K,
        value: V,
    ) {
        let mut storage = map.borrow_mut();
        storage.keys_map.insert(id.clone(), key);
        storage.values_map.insert(id, value);
    }

    pub fn enumValueMapGetCloned<
        K: Clone + Send + Sync + 'static + std::fmt::Debug,
        V: Clone + Send + Sync + 'static + std::fmt::Debug,
    >(
        map: crate::HxRef<crate::haxe_ds_enum_value_map::EnumValueMap<K, V>>,
        id: String,
    ) -> Option<V> {
        map.borrow().values_map.get(&id).cloned()
    }

    pub fn enumValueMapExists<
        K: Clone + Send + Sync + 'static + std::fmt::Debug,
        V: Clone + Send + Sync + 'static + std::fmt::Debug,
    >(
        map: crate::HxRef<crate::haxe_ds_enum_value_map::EnumValueMap<K, V>>,
        id: String,
    ) -> bool {
        map.borrow().values_map.contains_key(&id)
    }

    pub fn enumValueMapRemoveExists<
        K: Clone + Send + Sync + 'static + std::fmt::Debug,
        V: Clone + Send + Sync + 'static + std::fmt::Debug,
    >(
        map: crate::HxRef<crate::haxe_ds_enum_value_map::EnumValueMap<K, V>>,
        id: String,
    ) -> bool {
        let mut storage = map.borrow_mut();
        let existed = storage.values_map.remove(&id).is_some();
        storage.keys_map.remove(&id);
        existed
    }

    pub fn enumValueMapKeysOwned<
        K: Clone + Send + Sync + 'static + std::fmt::Debug,
        V: Clone + Send + Sync + 'static + std::fmt::Debug,
    >(
        map: crate::HxRef<crate::haxe_ds_enum_value_map::EnumValueMap<K, V>>,
    ) -> hxrt::iter::Iter<K> {
        hxrt::iter::Iter::from_vec(map.borrow().keys_map.values().cloned().collect::<Vec<_>>())
    }

    pub fn enumValueMapValuesOwned<
        K: Clone + Send + Sync + 'static + std::fmt::Debug,
        V: Clone + Send + Sync + 'static + std::fmt::Debug,
    >(
        map: crate::HxRef<crate::haxe_ds_enum_value_map::EnumValueMap<K, V>>,
    ) -> hxrt::iter::Iter<V> {
        hxrt::iter::Iter::from_vec(
            map.borrow()
                .values_map
                .values()
                .cloned()
                .collect::<Vec<_>>(),
        )
    }

    pub fn enumValueMapKeyValuesOwned<
        K: Clone + Send + Sync + 'static + std::fmt::Debug,
        V: Clone + Send + Sync + 'static + std::fmt::Debug,
    >(
        map: crate::HxRef<crate::haxe_ds_enum_value_map::EnumValueMap<K, V>>,
    ) -> hxrt::iter::Iter<hxrt::iter::KeyValue<K, V>> {
        hxrt::iter::Iter::from_vec({
            let storage = map.borrow();
            storage
                .values_map
                .iter()
                .map(|(id, value)| hxrt::iter::KeyValue {
                    key: storage.keys_map.get(id).unwrap().clone(),
                    value: value.clone(),
                })
                .collect::<Vec<_>>()
        })
    }

    pub fn enumValueMapCloneInto<
        K: Clone + Send + Sync + 'static + std::fmt::Debug,
        V: Clone + Send + Sync + 'static + std::fmt::Debug,
    >(
        dst: crate::HxRef<crate::haxe_ds_enum_value_map::EnumValueMap<K, V>>,
        src: crate::HxRef<crate::haxe_ds_enum_value_map::EnumValueMap<K, V>>,
    ) {
        let source = src.borrow();
        let mut out = dst.borrow_mut();
        out.keys_map = source.keys_map.clone();
        out.values_map = source.values_map.clone();
    }

    pub fn enumValueMapDebugString<
        K: Clone + Send + Sync + 'static + std::fmt::Debug,
        V: Clone + Send + Sync + 'static + std::fmt::Debug,
    >(
        map: crate::HxRef<crate::haxe_ds_enum_value_map::EnumValueMap<K, V>>,
    ) -> String {
        format!("{:?}", map.borrow().values_map)
    }

    pub fn enumValueMapClear<
        K: Clone + Send + Sync + 'static + std::fmt::Debug,
        V: Clone + Send + Sync + 'static + std::fmt::Debug,
    >(
        map: crate::HxRef<crate::haxe_ds_enum_value_map::EnumValueMap<K, V>>,
    ) {
        let mut storage = map.borrow_mut();
        storage.keys_map.clear();
        storage.values_map.clear();
    }
}
