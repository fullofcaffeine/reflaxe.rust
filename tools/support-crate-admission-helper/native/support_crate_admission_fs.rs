//! Safe operating-system facade for the Haxe-authored admission helper.
//!
//! Haxe owns traversal and admission policy. This file owns only bounded byte
//! operations and descriptor-relative filesystem calls that Haxe 4.3.7 cannot
//! express. It deliberately contains no product policy and uses only safe APIs.

use rustix::fd::OwnedFd;
use rustix::fs::{fstat, openat, Dir, FileType, Mode, OFlags, CWD};
use rustix::io::fcntl_dupfd_cloexec;
use std::fs::File;
use std::io::Read;
use std::os::unix::fs::MetadataExt;
use std::sync::Arc;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum AdmissionFsErrorKind {
    InvalidInput,
    NotFound,
    WrongKind,
    Io,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct AdmissionFsError {
    kind: AdmissionFsErrorKind,
}

impl AdmissionFsError {
    fn new(kind: AdmissionFsErrorKind) -> Self {
        Self { kind }
    }

    pub fn is_invalid_input(&self) -> bool {
        self.kind == AdmissionFsErrorKind::InvalidInput
    }

    pub fn is_not_found(&self) -> bool {
        self.kind == AdmissionFsErrorKind::NotFound
    }

    pub fn is_wrong_kind(&self) -> bool {
        self.kind == AdmissionFsErrorKind::WrongKind
    }

    pub fn is_io(&self) -> bool {
        self.kind == AdmissionFsErrorKind::Io
    }
}

#[derive(Debug)]
pub struct AdmissionFsErrorFactory;

impl AdmissionFsErrorFactory {
    pub fn invalid_input() -> AdmissionFsError {
        AdmissionFsError::new(AdmissionFsErrorKind::InvalidInput)
    }
}

#[derive(Clone, Debug)]
pub struct PinnedDirectory {
    fd: Arc<OwnedFd>,
}

#[derive(Clone, Debug)]
pub struct PinnedChild {
    fd: Arc<OwnedFd>,
    kind: FileType,
}

#[derive(Debug)]
pub struct AdmissionByteTools;

impl AdmissionByteTools {
    pub fn length(bytes: &Vec<i32>) -> i32 {
        i32::try_from(bytes.len()).unwrap_or(i32::MAX)
    }

    pub fn get(bytes: &Vec<i32>, index: i32) -> i32 {
        usize::try_from(index)
            .ok()
            .and_then(|value| bytes.get(value))
            .copied()
            .unwrap_or(-1)
    }

    pub fn append(mut target: Vec<i32>, source: Vec<i32>) -> Vec<i32> {
        target.extend(source);
        target
    }

    pub fn append_byte(mut target: Vec<i32>, value: i32) -> Vec<i32> {
        target.push(value);
        target
    }

    pub fn equal(left: &Vec<i32>, right: &Vec<i32>) -> bool {
        left == right
    }

    pub fn decode_utf8(bytes: Vec<i32>) -> Result<String, AdmissionFsError> {
        let bytes = checked_bytes(bytes)?;
        String::from_utf8(bytes)
            .map_err(|_| AdmissionFsError::new(AdmissionFsErrorKind::InvalidInput))
    }

    pub fn encode_utf8(value: String) -> Vec<i32> {
        value.into_bytes().into_iter().map(i32::from).collect()
    }

    pub fn compare_utf8(left: String, right: String) -> i32 {
        match left.as_bytes().cmp(right.as_bytes()) {
            std::cmp::Ordering::Less => -1,
            std::cmp::Ordering::Equal => 0,
            std::cmp::Ordering::Greater => 1,
        }
    }

    pub fn utf8_length(value: String) -> i32 {
        i32::try_from(value.len()).unwrap_or(i32::MAX)
    }
}

impl PinnedDirectory {
    pub fn open_current() -> Result<Self, AdmissionFsError> {
        Self::open_from(CWD, ".")
    }

    pub fn open_root() -> Result<Self, AdmissionFsError> {
        Self::open_from(CWD, "/")
    }

    pub fn open_directory(&self, component: String) -> Result<Self, AdmissionFsError> {
        validate_component(&component, true)?;
        Self::open_from(self.fd.as_ref(), &component)
    }

    pub fn entry_names(
        &self,
        maximum_entries: i32,
        maximum_name_bytes: i32,
        maximum_segment_bytes: i32,
    ) -> Result<Vec<String>, AdmissionFsError> {
        let maximum_entries = usize::try_from(maximum_entries)
            .map_err(|_| AdmissionFsError::new(AdmissionFsErrorKind::InvalidInput))?;
        let maximum_name_bytes = usize::try_from(maximum_name_bytes)
            .map_err(|_| AdmissionFsError::new(AdmissionFsErrorKind::InvalidInput))?;
        let maximum_segment_bytes = usize::try_from(maximum_segment_bytes)
            .map_err(|_| AdmissionFsError::new(AdmissionFsErrorKind::InvalidInput))?;
        let mut names = Vec::new();
        let mut name_bytes = 0usize;
        let directory = Dir::read_from(self.fd.as_ref()).map_err(classify_errno)?;
        for entry in directory {
            let entry = entry.map_err(classify_errno)?;
            let bytes = entry.file_name().to_bytes();
            if bytes == b"." || bytes == b".." {
                continue;
            }
            let name = std::str::from_utf8(bytes)
                .map_err(|_| AdmissionFsError::new(AdmissionFsErrorKind::InvalidInput))?;
            validate_component(name, false)?;
            if bytes.len() > maximum_segment_bytes {
                return Err(AdmissionFsError::new(AdmissionFsErrorKind::InvalidInput));
            }
            if names.len() >= maximum_entries {
                return Err(AdmissionFsError::new(AdmissionFsErrorKind::InvalidInput));
            }
            name_bytes = name_bytes
                .checked_add(bytes.len())
                .filter(|value| *value <= maximum_name_bytes)
                .ok_or_else(|| AdmissionFsError::new(AdmissionFsErrorKind::InvalidInput))?;
            names.push(name.to_owned());
        }
        names.sort_by(|left, right| left.as_bytes().cmp(right.as_bytes()));
        if names
            .windows(2)
            .any(|pair| pair[0].as_bytes() == pair[1].as_bytes())
        {
            return Err(AdmissionFsError::new(AdmissionFsErrorKind::InvalidInput));
        }
        Ok(names)
    }

    pub fn inspect_child(&self, component: String) -> Result<PinnedChild, AdmissionFsError> {
        validate_component(&component, false)?;
        // Acquire the exact child once. Keeping only a pathname plus inode is
        // insufficient because a filesystem may later reuse the same inode.
        // O_NONBLOCK ensures that opening a FIFO cannot wait for a writer.
        let fd = openat(
            self.fd.as_ref(),
            component.as_str(),
            OFlags::RDONLY | OFlags::NONBLOCK | OFlags::CLOEXEC | OFlags::NOFOLLOW,
            Mode::empty(),
        )
        .map_err(classify_errno)?;
        let identity = fstat(&fd).map_err(classify_errno)?;
        Ok(PinnedChild {
            fd: Arc::new(fd),
            kind: FileType::from_raw_mode(identity.st_mode),
        })
    }

    fn open_from<Fd: rustix::fd::AsFd>(
        parent: Fd,
        component: &str,
    ) -> Result<Self, AdmissionFsError> {
        let fd = openat(
            parent,
            component,
            OFlags::RDONLY | OFlags::DIRECTORY | OFlags::CLOEXEC | OFlags::NOFOLLOW,
            Mode::empty(),
        )
        .map_err(classify_errno)?;
        Ok(Self { fd: Arc::new(fd) })
    }
}

impl PinnedChild {
    pub fn open_directory(&self) -> Result<PinnedDirectory, AdmissionFsError> {
        if !self.kind.is_dir() {
            return Err(AdmissionFsError::new(AdmissionFsErrorKind::WrongKind));
        }
        Ok(PinnedDirectory {
            fd: self.fd.clone(),
        })
    }

    pub fn read_file(&self, maximum_bytes: i32) -> Result<Vec<i32>, AdmissionFsError> {
        if !self.kind.is_file() {
            return Err(AdmissionFsError::new(AdmissionFsErrorKind::WrongKind));
        }
        let maximum = usize::try_from(maximum_bytes)
            .ok()
            .filter(|value| *value > 0)
            .ok_or_else(|| AdmissionFsError::new(AdmissionFsErrorKind::InvalidInput))?;

        // Duplicate the retained descriptor so File can own its read cursor.
        // This operation cannot redirect the read through a replaced name.
        let fd = fcntl_dupfd_cloexec(self.fd.as_ref(), 0).map_err(classify_errno)?;
        let mut file = File::from(fd);
        let metadata = file.metadata().map_err(classify_io)?;
        if !metadata.is_file() || metadata.nlink() != 1 {
            return Err(AdmissionFsError::new(AdmissionFsErrorKind::WrongKind));
        }
        let mut bytes = Vec::new();
        file.by_ref()
            .take((maximum + 1) as u64)
            .read_to_end(&mut bytes)
            .map_err(classify_io)?;
        if bytes.len() > maximum {
            return Err(AdmissionFsError::new(AdmissionFsErrorKind::InvalidInput));
        }
        Ok(bytes.into_iter().map(i32::from).collect())
    }
}

fn validate_component(value: &str, allow_parent: bool) -> Result<(), AdmissionFsError> {
    if value.is_empty()
        || value == "."
        || (!allow_parent && value == "..")
        || value.as_bytes().contains(&0)
        || value.as_bytes().contains(&b'/')
        || value.as_bytes().contains(&b'\\')
        || value
            .as_bytes()
            .iter()
            .any(|byte| *byte < 0x20 || *byte == 0x7f)
    {
        return Err(AdmissionFsError::new(AdmissionFsErrorKind::InvalidInput));
    }
    Ok(())
}

fn classify_errno(error: rustix::io::Errno) -> AdmissionFsError {
    if error == rustix::io::Errno::NOENT {
        AdmissionFsError::new(AdmissionFsErrorKind::NotFound)
    } else if error == rustix::io::Errno::NOTDIR || error == rustix::io::Errno::LOOP {
        AdmissionFsError::new(AdmissionFsErrorKind::WrongKind)
    } else {
        AdmissionFsError::new(AdmissionFsErrorKind::Io)
    }
}

fn classify_io(_error: std::io::Error) -> AdmissionFsError {
    AdmissionFsError::new(AdmissionFsErrorKind::Io)
}

fn checked_bytes(values: Vec<i32>) -> Result<Vec<u8>, AdmissionFsError> {
    values
        .into_iter()
        .map(|value| {
            u8::try_from(value)
                .map_err(|_| AdmissionFsError::new(AdmissionFsErrorKind::InvalidInput))
        })
        .collect()
}
