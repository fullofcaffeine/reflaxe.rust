use crate::array::Array;
use crate::cell::HxRef;
use crate::dynamic::{self, Dynamic};

/// `hxrt::db`
///
/// Runtime helpers for `sys.db.*` implementations on the Rust target.
///
/// Why
/// - `sys.db.ResultSet` exposes a stateful, cursor-based API (`hasNext` / `next` plus "current row"
///   accessors like `getResult(n)`).
/// - The Rust target keeps most heavy lifting in framework code, but it is useful to have a small,
///   dependency-free runtime container for query results so both SQLite and MySQL backends can share
///   the cursor behavior.
///
/// What
/// - `QueryResult`: a list of field names and a list of rows (each row is a list of dynamic values).
/// - Cursor tracking (`idx`, `current`) so `getResult*` reads from the last fetched row.
///
/// How
/// - DB backends build `QueryResult` from concrete driver values, then hand it to `sys.db.ResultSet`
///   implementations.
/// - `next_row_object` converts the current row into a runtime dynamic-object (`DynObject`) so
///   user code can access `row.field` when `row` is `Dynamic`.
#[derive(Clone, Debug, Default)]
pub struct QueryResult {
    names: Array<String>,
    rows: Array<Array<Dynamic>>,
    idx: usize,
    current: Option<Array<Dynamic>>,
}

#[inline]
pub fn query_result_new(names: Array<String>, rows: Array<Array<Dynamic>>) -> HxRef<QueryResult> {
    HxRef::new(QueryResult {
        names,
        rows,
        idx: 0,
        current: None,
    })
}

#[inline]
pub fn query_result_length(q: &HxRef<QueryResult>) -> i32 {
    let b = q.borrow();
    let total = b.rows.len();
    let idx = b.idx.min(total);
    (total - idx) as i32
}

#[inline]
pub fn query_result_nfields(q: &HxRef<QueryResult>) -> i32 {
    q.borrow().names.len() as i32
}

#[inline]
pub fn query_result_has_next(q: &HxRef<QueryResult>) -> bool {
    let b = q.borrow();
    b.idx < b.rows.len()
}

#[inline]
pub fn query_result_fields(q: &HxRef<QueryResult>) -> Array<String> {
    q.borrow().names.clone()
}

pub fn query_result_next(q: &HxRef<QueryResult>) -> Option<Array<Dynamic>> {
    let mut b = q.borrow_mut();
    if b.idx >= b.rows.len() {
        b.current = None;
        return None;
    }
    let row = b
        .rows
        .get(b.idx)
        .unwrap_or_else(|| panic!("query_result_next: out of bounds"));
    b.idx += 1;
    b.current = Some(row.clone());
    Some(row)
}

/// Advance the cursor and return a `Dynamic` row object (or `null` at end-of-result).
pub fn query_result_next_row_object(q: &HxRef<QueryResult>) -> Dynamic {
    let row = match query_result_next(q) {
        None => return Dynamic::null(),
        Some(r) => r,
    };

    let names: Vec<String> = q.borrow().names.to_vec();
    let values: Vec<Dynamic> = row.to_vec();

    let obj = dynamic::dyn_object_new();
    let len = names.len().min(values.len());
    for i in 0..len {
        dynamic::dyn_object_set(&obj, names[i].as_str(), values[i].clone());
    }
    Dynamic::from(obj)
}

/// Get the value of the `n`th column of the current row as a string.
///
/// Returns `""` if there is no current row or if the index is out of bounds.
pub fn query_result_get_result(q: &HxRef<QueryResult>, n: i32) -> String {
    let b = q.borrow();
    let Some(row) = b.current.as_ref() else {
        return String::new();
    };
    let idx = n.max(0) as usize;
    let Some(v) = row.get(idx) else {
        return String::new();
    };

    // Preserve a stable "no-null" surface for now.
    // If the value is Dynamic-null, return empty string.
    if v.is_null() {
        return String::new();
    }
    v.to_haxe_string()
}

pub fn query_result_get_int_result(q: &HxRef<QueryResult>, n: i32) -> i32 {
    let s = query_result_get_result(q, n);
    s.parse::<i32>().unwrap_or(0)
}

pub fn query_result_get_float_result(q: &HxRef<QueryResult>, n: i32) -> f64 {
    let s = query_result_get_result(q, n);
    s.parse::<f64>().unwrap_or(0.0)
}
