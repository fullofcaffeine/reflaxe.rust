/// `file_native`
///
/// Typed helper module backing `sys.io.File`.
#[derive(Debug)]
pub struct FileNative;

#[allow(non_snake_case)]
impl FileNative {
    pub fn getContent<P: AsRef<str>>(path: P) -> String {
        match std::fs::read_to_string(path.as_ref()) {
            Ok(s) => s,
            Err(e) => hxrt::exception::throw(hxrt::dynamic::from(format!("{}", e))),
        }
    }

    pub fn saveContent<P: AsRef<str>, C: AsRef<str>>(path: P, content: C) {
        match std::fs::write(path.as_ref(), content.as_ref().as_bytes()) {
            Ok(()) => (),
            Err(e) => hxrt::exception::throw(hxrt::dynamic::from(format!("{}", e))),
        }
    }

    pub fn getBytes<P: AsRef<str>>(path: P) -> crate::HxRef<hxrt::bytes::Bytes> {
        let data = match std::fs::read(path.as_ref()) {
            Ok(b) => b,
            Err(e) => hxrt::exception::throw(hxrt::dynamic::from(format!("{}", e))),
        };
        crate::HxRef::new(hxrt::bytes::Bytes::from_vec(data))
    }

    pub fn saveBytes<P: AsRef<str>>(path: P, bytes: crate::HxRef<hxrt::bytes::Bytes>) {
        let b = bytes.borrow();
        match std::fs::write(path.as_ref(), b.as_slice()) {
            Ok(()) => (),
            Err(e) => hxrt::exception::throw(hxrt::dynamic::from(format!("{}", e))),
        }
    }

    pub fn openRead<P: AsRef<str>>(path: P) -> crate::HxRef<hxrt::fs::FileHandle> {
        hxrt::fs::open_read(path.as_ref())
    }

    pub fn openWriteTruncate<P: AsRef<str>>(path: P) -> crate::HxRef<hxrt::fs::FileHandle> {
        hxrt::fs::open_write_truncate(path.as_ref())
    }

    pub fn openAppend<P: AsRef<str>>(path: P) -> crate::HxRef<hxrt::fs::FileHandle> {
        hxrt::fs::open_append(path.as_ref())
    }

    pub fn openUpdate<P: AsRef<str>>(path: P) -> crate::HxRef<hxrt::fs::FileHandle> {
        hxrt::fs::open_update(path.as_ref())
    }

    pub fn copy<S: AsRef<str>, D: AsRef<str>>(srcPath: S, dstPath: D) {
        match std::fs::copy(srcPath.as_ref(), dstPath.as_ref()) {
            Ok(_) => (),
            Err(e) => hxrt::exception::throw(hxrt::dynamic::from(format!("{}", e))),
        }
    }

    pub fn close(handle: crate::HxRef<hxrt::fs::FileHandle>) {
        handle.borrow_mut().close();
    }

    pub fn readByte(handle: crate::HxRef<hxrt::fs::FileHandle>) -> i32 {
        handle.borrow_mut().read_byte()
    }

    pub fn readBytes(
        handle: crate::HxRef<hxrt::fs::FileHandle>,
        bytes: crate::HxRef<hxrt::bytes::Bytes>,
        pos: i32,
        len: i32,
    ) -> i32 {
        let mut buf = vec![0u8; len as usize];
        let n = handle.borrow_mut().read_into(buf.as_mut_slice());
        if n <= 0 {
            -1
        } else {
            hxrt::bytes::write_from_slice(&bytes, pos, &buf[0..(n as usize)]);
            n
        }
    }

    pub fn writeByte(handle: crate::HxRef<hxrt::fs::FileHandle>, byte: i32) {
        let buf = [(byte & 0xFF) as u8];
        handle.borrow_mut().write_all(&buf);
    }

    pub fn writeBytes(
        handle: crate::HxRef<hxrt::fs::FileHandle>,
        bytes: crate::HxRef<hxrt::bytes::Bytes>,
        pos: i32,
        len: i32,
    ) -> i32 {
        let b = bytes.borrow();
        let data = b.as_slice();
        let start = pos as usize;
        let end = (pos + len) as usize;
        handle.borrow_mut().write_all(&data[start..end]);
        len
    }

    pub fn flush(handle: crate::HxRef<hxrt::fs::FileHandle>) {
        handle.borrow_mut().flush();
    }

    pub fn seekFromStart(handle: crate::HxRef<hxrt::fs::FileHandle>, pos: i32) {
        handle.borrow_mut().seek_from_start(pos as u64);
    }

    pub fn seekFromCurrent(handle: crate::HxRef<hxrt::fs::FileHandle>, offset: i32) {
        handle.borrow_mut().seek_from_current(offset as i64);
    }

    pub fn seekFromEnd(handle: crate::HxRef<hxrt::fs::FileHandle>, offset: i32) {
        handle.borrow_mut().seek_from_end(offset as i64);
    }

    pub fn tell(handle: crate::HxRef<hxrt::fs::FileHandle>) -> i32 {
        handle.borrow_mut().tell()
    }

    pub fn eof(handle: crate::HxRef<hxrt::fs::FileHandle>) -> bool {
        handle.borrow_mut().eof()
    }
}
