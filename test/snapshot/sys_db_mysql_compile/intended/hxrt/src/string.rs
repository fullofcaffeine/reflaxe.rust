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
