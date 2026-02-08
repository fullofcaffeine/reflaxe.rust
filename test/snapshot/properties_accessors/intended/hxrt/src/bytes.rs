use crate::exception;
use std::fmt;
use std::{cell::RefCell, rc::Rc};

#[derive(Debug)]
pub struct Bytes {
    data: Vec<u8>,
}

fn check_index(op: &str, pos: i32, len: i32) {
    if pos < 0 || pos >= len {
        let _ = op;
        exception::throw(crate::dynamic::from(crate::io::Error::OutsideBounds));
    }
}

fn check_range(op: &str, pos: i32, range_len: i32, len: i32) {
    if range_len < 0 {
        let _ = op;
        exception::throw(crate::dynamic::from(crate::io::Error::OutsideBounds));
    }
    // allow empty ranges at pos == len
    if pos < 0 || pos > len || pos + range_len > len {
        let _ = op;
        exception::throw(crate::dynamic::from(crate::io::Error::OutsideBounds));
    }
}

impl fmt::Display for Bytes {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let s = String::from_utf8_lossy(&self.data);
        write!(f, "{}", s)
    }
}

impl Bytes {
    pub fn alloc(size: usize) -> Bytes {
        Bytes {
            data: vec![0u8; size],
        }
    }

    pub fn from_vec(data: Vec<u8>) -> Bytes {
        Bytes { data }
    }

    pub fn of_string(s: &str) -> Bytes {
        Bytes {
            data: s.as_bytes().to_vec(),
        }
    }

    pub fn length(&self) -> i32 {
        self.data.len() as i32
    }

    pub fn get(&self, pos: i32) -> i32 {
        let len = self.length();
        check_index("get", pos, len);
        self.data[pos as usize] as i32
    }

    pub fn set(&mut self, pos: i32, value: i32) {
        let len = self.length();
        check_index("set", pos, len);
        self.data[pos as usize] = value as u8;
    }

    pub fn sub(&self, pos: i32, len: i32) -> Bytes {
        let total = self.length();
        check_range("sub", pos, len, total);
        let start = pos as usize;
        let end = (pos + len) as usize;
        Bytes {
            data: self.data[start..end].to_vec(),
        }
    }

    pub fn get_string(&self, pos: i32, len: i32) -> String {
        let total = self.length();
        check_range("getString", pos, len, total);
        let start = pos as usize;
        let end = (pos + len) as usize;
        String::from_utf8_lossy(&self.data[start..end]).into_owned()
    }

    pub fn as_slice(&self) -> &[u8] {
        self.data.as_slice()
    }
}

/// Copy `len` bytes from `src[srcpos..]` into `dst[pos..]`.
///
/// This is implemented as a helper that operates on Haxe refs (`Rc<RefCell<...>>`) so we can avoid
/// borrow conflicts when `src` and `dst` alias (it behaves like a memmove: we copy via a temporary).
pub fn blit(dst: &Rc<RefCell<Bytes>>, pos: i32, src: &Rc<RefCell<Bytes>>, srcpos: i32, len: i32) {
    if len == 0 {
        return;
    }

    // Read from src into a temporary while holding only an immutable borrow.
    let tmp: Vec<u8> = {
        let src_b = src.borrow();
        let src_len = src_b.length();
        check_range("blit", srcpos, len, src_len);
        let start = srcpos as usize;
        let end = (srcpos + len) as usize;
        src_b.data[start..end].to_vec()
    };

    // Write into dst after the src borrow has ended.
    let mut dst_b = dst.borrow_mut();
    let dst_len = dst_b.length();
    check_range("blit", pos, len, dst_len);
    let start = pos as usize;
    let end = (pos + len) as usize;
    dst_b.data[start..end].copy_from_slice(&tmp);
}

/// Write `src` bytes into `dst` starting at `pos`.
///
/// This is used by runtime-backed IO implementations (e.g. `sys.io.FileInput`) to efficiently
/// fill a `haxe.io.Bytes` buffer without going through per-byte `set()` calls.
pub fn write_from_slice(dst: &Rc<RefCell<Bytes>>, pos: i32, src: &[u8]) {
    if src.is_empty() {
        return;
    }

    let len = src.len() as i32;
    let mut dst_b = dst.borrow_mut();
    let dst_len = dst_b.length();
    check_range("write_from_slice", pos, len, dst_len);
    let start = pos as usize;
    let end = (pos + len) as usize;
    dst_b.data[start..end].copy_from_slice(src);
}
