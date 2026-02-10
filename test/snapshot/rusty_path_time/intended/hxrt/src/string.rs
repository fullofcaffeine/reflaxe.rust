/// Nullable Haxe `String` representation.
///
/// Why
/// - In Haxe, `String` is a reference type and can be `null` by default.
/// - Rust's `String` is an owned value and cannot represent `null` without a wrapper.
///
/// What
/// - Wraps `Option<String>`.
/// - `Default` is `null`, so uninitialized locals/fields match Haxe semantics.
///
/// How
/// - `as_str()` throws a catchable Haxe exception on null dereference ("Null Access").
/// - `to_haxe_string()` matches `Std.string` behavior: null becomes `"null"`.
#[derive(Clone, Debug, Default)]
pub struct HxString(Option<String>);

impl HxString {
    #[inline]
    pub fn new(s: String) -> Self {
        Self(Some(s))
    }

    #[inline]
    pub fn null() -> Self {
        Self(None)
    }

    #[inline]
    pub fn is_null(&self) -> bool {
        self.0.is_none()
    }

    #[inline]
    pub fn is_some(&self) -> bool {
        self.0.is_some()
    }

    #[inline]
    pub fn as_str(&self) -> &str {
        match &self.0 {
            Some(s) => s.as_str(),
            None => crate::exception::throw(crate::dynamic::from(String::from("Null Access"))),
        }
    }

    #[inline]
    pub fn to_haxe_string(&self) -> String {
        match &self.0 {
            Some(s) => s.clone(),
            None => String::from("null"),
        }
    }
}

impl From<&str> for HxString {
    #[inline]
    fn from(value: &str) -> Self {
        Self::new(String::from(value))
    }
}

impl From<String> for HxString {
    #[inline]
    fn from(value: String) -> Self {
        Self::new(value)
    }
}

impl std::fmt::Display for HxString {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.to_haxe_string())
    }
}

pub fn parse_float(s: &str) -> f64 {
    s.parse::<f64>().unwrap_or(f64::NAN)
}

#[inline]
pub fn len(s: &str) -> i32 {
    s.chars().count() as i32
}

fn byte_index_at_char(s: &str, char_index: i32) -> usize {
    let idx = char_index.max(0) as usize;
    if idx == 0 {
        return 0;
    }
    s.char_indices()
        .nth(idx)
        .map(|(byte_i, _)| byte_i)
        .unwrap_or(s.len())
}

#[inline]
pub fn char_at(s: &str, index: i32) -> String {
    if index < 0 {
        return String::new();
    }
    s.chars()
        .nth(index as usize)
        .map(|c| c.to_string())
        .unwrap_or_default()
}

/// Haxe `String.charCodeAt(index)`.
///
/// Returns `None` for out-of-bounds indices.
///
/// Note: reflaxe.rust currently treats indices as Unicode scalar indices (`char`), which matches
/// the rest of `hxrt::string` helpers used by upstream stdlib (ASCII-heavy paths like Base64
/// are unaffected).
#[inline]
pub fn char_code_at(s: &str, index: i32) -> Option<i32> {
    if index < 0 {
        return None;
    }
    s.chars().nth(index as usize).map(|c| c as u32 as i32)
}

/// Haxe-like `substr(pos, ?len)` on Unicode scalar indices.
pub fn substr(s: &str, pos: i32, length: Option<i32>) -> String {
    let total = len(s);
    let mut start = pos;
    if start < 0 {
        start += total;
    }
    if start < 0 {
        start = 0;
    }
    if start > total {
        start = total;
    }

    let mut end = match length {
        None => total,
        Some(l) => {
            if l <= 0 {
                start
            } else {
                (start + l).min(total)
            }
        }
    };
    if end < start {
        end = start;
    }

    let start_b = byte_index_at_char(s, start);
    let end_b = byte_index_at_char(s, end);
    s.get(start_b..end_b).unwrap_or("").to_string()
}

#[inline]
pub fn to_lower_case(s: &str) -> String {
    s.to_lowercase()
}

pub fn index_of(s: &str, sub: &str, from_index: Option<i32>) -> i32 {
    let total = len(s);
    let mut from = from_index.unwrap_or(0);
    if from < 0 {
        from = 0;
    }
    if from > total {
        return -1;
    }
    let start_b = byte_index_at_char(s, from);
    let hay = &s[start_b..];
    let Some(off_b) = hay.find(sub) else {
        return -1;
    };

    // Convert byte offset to char index.
    let upto = &s[..start_b + off_b];
    len(upto)
}

pub fn split(s: &str, delim: &str) -> crate::array::Array<String> {
    if delim.is_empty() {
        return crate::array::Array::from_vec(s.chars().map(|c| c.to_string()).collect());
    }
    crate::array::Array::from_vec(s.split(delim).map(|x| x.to_string()).collect())
}

/// Haxe `String.fromCharCode(code)`.
///
/// Haxe's behavior for invalid values is "unspecified"; this runtime returns `""` for
/// negative values or code points outside the Unicode scalar range.
pub fn from_char_code(code: i32) -> String {
    if code < 0 {
        return String::new();
    }
    let u = code as u32;
    match char::from_u32(u) {
        Some(c) => c.to_string(),
        None => String::new(),
    }
}
