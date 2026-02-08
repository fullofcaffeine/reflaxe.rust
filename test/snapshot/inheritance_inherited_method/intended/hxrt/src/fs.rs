use crate::{dynamic, exception};
use std::{cell::RefCell, fs, io, rc::Rc};

/// Minimal file IO runtime for `sys.io.*`.
///
/// Why
/// - Haxe declares `sys.io.FileInput` / `sys.io.FileOutput` as extern types whose concrete
///   implementations are target-provided.
/// - On reflaxe.rust we must keep a handle open across calls, support `seek/tell`, and ensure
///   IO failures are catchable Haxe exceptions (not `unwrap()` panics).
///
/// What
/// - `FileHandle` wraps an `Option<fs::File>` behind `Rc<RefCell<...>>` (via `HxRef<T>` in emitted
///   code). The `Option` enables `close()` semantics without requiring `std::fs::File: Clone`.
///
/// How
/// - Public constructors `open_read` / `open_*` return `Rc<RefCell<FileHandle>>`.
/// - Errors throw via `hxrt::exception::throw(hxrt::dynamic::from(String))`.
/// - EOF is signaled by returning `-1` from `read_byte` / `read_into`.
#[derive(Debug)]
pub struct FileHandle {
    file: Option<fs::File>,
}

fn throw_io(op: &str, err: io::Error) -> ! {
    let _ = op;
    exception::throw(dynamic::from(format!("{}", err)))
}

fn throw_closed() -> ! {
    exception::throw(dynamic::from(String::from("File handle is closed")))
}

impl FileHandle {
    fn with_file_mut<R>(&mut self, f: impl FnOnce(&mut fs::File) -> R) -> R {
        match self.file.as_mut() {
            Some(file) => f(file),
            None => throw_closed(),
        }
    }

    pub fn close(&mut self) {
        self.file = None;
    }

    pub fn read_byte(&mut self) -> i32 {
        self.with_file_mut(|file| {
            let mut buf = [0u8; 1];
            match io::Read::read(file, &mut buf) {
                Ok(0) => -1,
                Ok(_) => buf[0] as i32,
                Err(e) => throw_io("read_byte", e),
            }
        })
    }

    pub fn read_into(&mut self, buf: &mut [u8]) -> i32 {
        self.with_file_mut(|file| match io::Read::read(file, buf) {
            Ok(0) => -1,
            Ok(n) => n as i32,
            Err(e) => throw_io("read_into", e),
        })
    }

    pub fn write_all(&mut self, buf: &[u8]) {
        self.with_file_mut(|file| match io::Write::write_all(file, buf) {
            Ok(()) => (),
            Err(e) => throw_io("write_all", e),
        })
    }

    pub fn flush(&mut self) {
        self.with_file_mut(|file| {
            let _ = io::Write::flush(file);
        })
    }

    pub fn seek_from_start(&mut self, pos: u64) {
        self.with_file_mut(
            |file| match io::Seek::seek(file, io::SeekFrom::Start(pos)) {
                Ok(_) => (),
                Err(e) => throw_io("seek_start", e),
            },
        )
    }

    pub fn seek_from_current(&mut self, offset: i64) {
        self.with_file_mut(
            |file| match io::Seek::seek(file, io::SeekFrom::Current(offset)) {
                Ok(_) => (),
                Err(e) => throw_io("seek_current", e),
            },
        )
    }

    pub fn seek_from_end(&mut self, offset: i64) {
        self.with_file_mut(
            |file| match io::Seek::seek(file, io::SeekFrom::End(offset)) {
                Ok(_) => (),
                Err(e) => throw_io("seek_end", e),
            },
        )
    }

    pub fn tell(&mut self) -> i32 {
        self.with_file_mut(|file| match io::Seek::stream_position(file) {
            Ok(p) => p as i32,
            Err(e) => throw_io("tell", e),
        })
    }

    pub fn eof(&mut self) -> bool {
        self.with_file_mut(|file| {
            let pos = match io::Seek::stream_position(file) {
                Ok(p) => p,
                Err(e) => throw_io("eof.tell", e),
            };
            let len = match file.metadata() {
                Ok(m) => m.len(),
                Err(e) => throw_io("eof.metadata", e),
            };
            pos >= len
        })
    }
}

pub fn open_read(path: &str) -> Rc<RefCell<FileHandle>> {
    let file = match fs::File::open(path) {
        Ok(f) => f,
        Err(e) => throw_io("open_read", e),
    };
    Rc::new(RefCell::new(FileHandle { file: Some(file) }))
}

pub fn open_write_truncate(path: &str) -> Rc<RefCell<FileHandle>> {
    let file = match fs::OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(true)
        .open(path)
    {
        Ok(f) => f,
        Err(e) => throw_io("open_write_truncate", e),
    };
    Rc::new(RefCell::new(FileHandle { file: Some(file) }))
}

pub fn open_append(path: &str) -> Rc<RefCell<FileHandle>> {
    let file = match fs::OpenOptions::new().create(true).append(true).open(path) {
        Ok(f) => f,
        Err(e) => throw_io("open_append", e),
    };
    Rc::new(RefCell::new(FileHandle { file: Some(file) }))
}

pub fn open_update(path: &str) -> Rc<RefCell<FileHandle>> {
    let file = match fs::OpenOptions::new()
        .create(true)
        .read(true)
        .write(true)
        .truncate(false)
        .open(path)
    {
        Ok(f) => f,
        Err(e) => throw_io("open_update", e),
    };
    Rc::new(RefCell::new(FileHandle { file: Some(file) }))
}
