use crate::cell::HxRef;
use crate::exception;
use std::fmt;

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

fn read_exact<const N: usize>(buf: &HxRef<Bytes>, pos: i32, op: &str) -> [u8; N] {
    let borrowed = buf.borrow();
    let total = borrowed.length();
    check_range(op, pos, N as i32, total);
    let start = pos as usize;
    let end = start + N;
    let mut out = [0u8; N];
    out.copy_from_slice(&borrowed.data[start..end]);
    out
}

fn write_exact<const N: usize>(buf: &HxRef<Bytes>, pos: i32, bytes: [u8; N], op: &str) {
    let mut borrowed = buf.borrow_mut();
    let total = borrowed.length();
    check_range(op, pos, N as i32, total);
    let start = pos as usize;
    let end = start + N;
    borrowed.data[start..end].copy_from_slice(&bytes);
}

/// Fill `len` bytes starting at `pos` with `value & 0xFF`.
pub fn fill(buf: &HxRef<Bytes>, pos: i32, len: i32, value: i32) {
    if len == 0 {
        let borrowed = buf.borrow();
        check_range("fill", pos, 0, borrowed.length());
        return;
    }

    let mut borrowed = buf.borrow_mut();
    let total = borrowed.length();
    check_range("fill", pos, len, total);
    let start = pos as usize;
    let end = (pos + len) as usize;
    borrowed.data[start..end].fill(value as u8);
}

/// Lexicographic byte comparison matching upstream `haxe.io.Bytes.compare`.
pub fn compare(lhs: &HxRef<Bytes>, rhs: &HxRef<Bytes>) -> i32 {
    let lhs_b = lhs.borrow();
    let rhs_b = rhs.borrow();
    let len = lhs_b.data.len().min(rhs_b.data.len());

    for i in 0..len {
        let a = lhs_b.data[i] as i32;
        let b = rhs_b.data[i] as i32;
        if a != b {
            return a - b;
        }
    }

    lhs_b.length() - rhs_b.length()
}

/// Lowercase hexadecimal encoding matching upstream `Bytes.toHex()`.
pub fn to_hex(buf: &HxRef<Bytes>) -> String {
    let borrowed = buf.borrow();
    let mut out = String::with_capacity(borrowed.data.len() * 2);
    for byte in &borrowed.data {
        use std::fmt::Write;
        let _ = write!(&mut out, "{:02x}", byte);
    }
    out
}

/// Decode an even-length hexadecimal string using upstream Haxe semantics.
pub fn of_hex(s: &str) -> Bytes {
    let len = s.len();
    if (len & 1) != 0 {
        exception::throw(crate::dynamic::from(String::from(
            "Not a hex string (odd number of digits)",
        )));
    }

    let bytes = s.as_bytes();
    let mut out = vec![0u8; len >> 1];
    for i in 0..out.len() {
        let high = ((bytes[i * 2] as i32) & 0xF) + ((((bytes[i * 2] as i32) & 0x40) >> 6) * 9);
        let low =
            ((bytes[i * 2 + 1] as i32) & 0xF) + ((((bytes[i * 2 + 1] as i32) & 0x40) >> 6) * 9);
        out[i] = (((high << 4) | low) & 0xFF) as u8;
    }
    Bytes::from_vec(out)
}

pub fn get_u16(buf: &HxRef<Bytes>, pos: i32) -> i32 {
    u16::from_le_bytes(read_exact::<2>(buf, pos, "getUInt16")) as i32
}

pub fn set_u16(buf: &HxRef<Bytes>, pos: i32, value: i32) {
    write_exact(buf, pos, (value as u16).to_le_bytes(), "setUInt16");
}

pub fn get_i32(buf: &HxRef<Bytes>, pos: i32) -> i32 {
    i32::from_le_bytes(read_exact::<4>(buf, pos, "getInt32"))
}

pub fn set_i32(buf: &HxRef<Bytes>, pos: i32, value: i32) {
    write_exact(buf, pos, value.to_le_bytes(), "setInt32");
}

pub fn get_float(buf: &HxRef<Bytes>, pos: i32) -> f64 {
    f32::from_le_bytes(read_exact::<4>(buf, pos, "getFloat")) as f64
}

pub fn set_float(buf: &HxRef<Bytes>, pos: i32, value: f64) {
    write_exact(buf, pos, (value as f32).to_le_bytes(), "setFloat");
}

pub fn get_double(buf: &HxRef<Bytes>, pos: i32) -> f64 {
    f64::from_le_bytes(read_exact::<8>(buf, pos, "getDouble"))
}

pub fn set_double(buf: &HxRef<Bytes>, pos: i32, value: f64) {
    write_exact(buf, pos, value.to_le_bytes(), "setDouble");
}

/// Copy `len` bytes from `src[srcpos..]` into `dst[pos..]`.
///
/// This is implemented as a helper that operates on Haxe refs (`HxRef<...>`) so we can avoid
/// borrow conflicts when `src` and `dst` alias (it behaves like a memmove: we copy via a temporary).
pub fn blit(dst: &HxRef<Bytes>, pos: i32, src: &HxRef<Bytes>, srcpos: i32, len: i32) {
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
pub fn write_from_slice(dst: &HxRef<Bytes>, pos: i32, src: &[u8]) {
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
