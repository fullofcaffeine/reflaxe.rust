/// `hash_map_tools` (non-nullable string profile)
///
/// Typed helper module backing `rust.HashMapTools` when Haxe `String` lowers to
/// owned Rust `String` values (metal profile default).
#[derive(Debug)]
pub struct HashMapTools;

#[allow(non_snake_case)]
impl HashMapTools {
    pub fn getCloned<K: Eq + std::hash::Hash + Clone, V: Clone>(
        m: &std::collections::HashMap<K, V>,
        key: &K,
    ) -> Option<V> {
        m.get(key).cloned()
    }

    pub fn len<K, V>(m: &std::collections::HashMap<K, V>) -> i32 {
        m.len() as i32
    }

    pub fn insert<K: Eq + std::hash::Hash, V>(
        m: &mut std::collections::HashMap<K, V>,
        key: K,
        value: V,
    ) -> Option<V> {
        m.insert(key, value)
    }

    pub fn remove<K: Eq + std::hash::Hash, V>(
        m: &mut std::collections::HashMap<K, V>,
        key: &K,
    ) -> Option<V> {
        m.remove(key)
    }

    pub fn removeExists<K: Eq + std::hash::Hash, V>(
        m: &mut std::collections::HashMap<K, V>,
        key: &K,
    ) -> bool {
        m.remove(key).is_some()
    }

    pub fn keysOwned<K: Eq + std::hash::Hash + Clone, V>(
        m: &std::collections::HashMap<K, V>,
    ) -> hxrt::iter::Iter<K> {
        hxrt::iter::Iter::from_vec(m.keys().cloned().collect::<Vec<_>>())
    }

    pub fn valuesOwned<K: Eq + std::hash::Hash, V: Clone>(
        m: &std::collections::HashMap<K, V>,
    ) -> hxrt::iter::Iter<V> {
        hxrt::iter::Iter::from_vec(m.values().cloned().collect::<Vec<_>>())
    }

    pub fn keyValuesOwned<K: Eq + std::hash::Hash + Clone, V: Clone>(
        m: &std::collections::HashMap<K, V>,
    ) -> hxrt::iter::Iter<hxrt::iter::KeyValue<K, V>> {
        hxrt::iter::Iter::from_vec(
            m.iter()
                .map(|(k, v)| hxrt::iter::KeyValue {
                    key: k.clone(),
                    value: v.clone(),
                })
                .collect::<Vec<_>>(),
        )
    }

    pub fn debugString<K: Eq + std::hash::Hash + std::fmt::Debug, V: std::fmt::Debug>(
        m: &std::collections::HashMap<K, V>,
    ) -> String {
        format!("{:?}", m)
    }
}
