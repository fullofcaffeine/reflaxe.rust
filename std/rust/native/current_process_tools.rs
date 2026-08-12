use std::io::{Read, Write};

const MAX_CHUNK_BYTES: usize = 1024 * 1024;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum CurrentProcessErrorKind {
    InvalidInput,
    Read,
    Write,
    Flush,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CurrentProcessError {
    kind: CurrentProcessErrorKind,
}

impl CurrentProcessError {
    fn new(kind: CurrentProcessErrorKind) -> Self {
        Self { kind }
    }

    pub fn is_invalid_input(&self) -> bool {
        self.kind == CurrentProcessErrorKind::InvalidInput
    }

    pub fn is_read(&self) -> bool {
        self.kind == CurrentProcessErrorKind::Read
    }

    pub fn is_write(&self) -> bool {
        self.kind == CurrentProcessErrorKind::Write
    }

    pub fn is_flush(&self) -> bool {
        self.kind == CurrentProcessErrorKind::Flush
    }
}

pub struct CurrentProcess;

impl CurrentProcess {
    pub fn user_argument_count() -> Result<i32, CurrentProcessError> {
        let count = std::env::args_os().count().saturating_sub(1);
        i32::try_from(count)
            .map_err(|_| CurrentProcessError::new(CurrentProcessErrorKind::InvalidInput))
    }

    pub fn read_stdin_chunk(max_bytes: i32) -> Result<Vec<i32>, CurrentProcessError> {
        let max_bytes = Self::validate_read_size(max_bytes)?;
        let mut bytes = vec![0_u8; max_bytes];
        let read = std::io::stdin()
            .lock()
            .read(&mut bytes)
            .map_err(|_| CurrentProcessError::new(CurrentProcessErrorKind::Read))?;
        bytes.truncate(read);
        Ok(bytes.into_iter().map(i32::from).collect())
    }

    fn validate_read_size(max_bytes: i32) -> Result<usize, CurrentProcessError> {
        usize::try_from(max_bytes)
            .ok()
            .filter(|value| (1..=MAX_CHUNK_BYTES).contains(value))
            .ok_or_else(|| CurrentProcessError::new(CurrentProcessErrorKind::InvalidInput))
    }

    pub fn write_stdout(bytes: Vec<i32>) -> Result<(), CurrentProcessError> {
        let bytes = validated_bytes(bytes)?;
        let mut stdout = std::io::stdout().lock();
        stdout
            .write_all(&bytes)
            .map_err(|_| CurrentProcessError::new(CurrentProcessErrorKind::Write))?;
        stdout
            .flush()
            .map_err(|_| CurrentProcessError::new(CurrentProcessErrorKind::Flush))?;
        Ok(())
    }

    pub fn write_stderr_utf8(message: String) -> Result<(), CurrentProcessError> {
        Self::validate_stderr_utf8(&message)?;
        let mut stderr = std::io::stderr().lock();
        stderr
            .write_all(message.as_bytes())
            .map_err(|_| CurrentProcessError::new(CurrentProcessErrorKind::Write))?;
        stderr
            .flush()
            .map_err(|_| CurrentProcessError::new(CurrentProcessErrorKind::Flush))?;
        Ok(())
    }

    fn validate_stderr_utf8(message: &str) -> Result<(), CurrentProcessError> {
        if message.len() <= MAX_CHUNK_BYTES {
            Ok(())
        } else {
            Err(CurrentProcessError::new(
                CurrentProcessErrorKind::InvalidInput,
            ))
        }
    }

    pub fn exit(code: i32) -> ! {
        std::process::exit(code)
    }
}

fn validated_bytes(values: Vec<i32>) -> Result<Vec<u8>, CurrentProcessError> {
    if values.len() > MAX_CHUNK_BYTES {
        return Err(CurrentProcessError::new(
            CurrentProcessErrorKind::InvalidInput,
        ));
    }
    values
        .into_iter()
        .map(|value| {
            u8::try_from(value)
                .map_err(|_| CurrentProcessError::new(CurrentProcessErrorKind::InvalidInput))
        })
        .collect()
}

#[cfg(test)]
mod tests {
    #[test]
    fn error_predicates_are_exact_and_disjoint() {
        let cases = [
            (
                super::CurrentProcessErrorKind::InvalidInput,
                [true, false, false, false],
            ),
            (
                super::CurrentProcessErrorKind::Read,
                [false, true, false, false],
            ),
            (
                super::CurrentProcessErrorKind::Write,
                [false, false, true, false],
            ),
            (
                super::CurrentProcessErrorKind::Flush,
                [false, false, false, true],
            ),
        ];

        for (kind, expected) in cases {
            let error = super::CurrentProcessError::new(kind);
            assert_eq!(
                [
                    error.is_invalid_input(),
                    error.is_read(),
                    error.is_write(),
                    error.is_flush(),
                ],
                expected
            );
        }
    }

    #[test]
    fn byte_payload_accepts_the_exact_limit_and_rejects_one_more() {
        assert_eq!(
            super::validated_bytes(vec![0; super::MAX_CHUNK_BYTES])
                .expect("exact byte limit must be accepted")
                .len(),
            super::MAX_CHUNK_BYTES
        );
        assert!(matches!(
            super::validated_bytes(vec![0; super::MAX_CHUNK_BYTES + 1]),
            Err(error) if error.is_invalid_input()
        ));
    }

    #[test]
    fn utf8_diagnostic_accepts_the_exact_limit_and_rejects_one_more() {
        assert!(
            super::CurrentProcess::validate_stderr_utf8(&"x".repeat(super::MAX_CHUNK_BYTES))
                .is_ok()
        );
        assert!(matches!(
            super::CurrentProcess::validate_stderr_utf8(&"x".repeat(super::MAX_CHUNK_BYTES + 1)),
            Err(error) if error.is_invalid_input()
        ));
    }

    #[test]
    fn stdin_read_size_accepts_the_exact_limit_and_rejects_one_more() {
        assert_eq!(
            super::CurrentProcess::validate_read_size(super::MAX_CHUNK_BYTES as i32)
                .expect("exact read limit must be accepted"),
            super::MAX_CHUNK_BYTES
        );
        assert!(matches!(
            super::CurrentProcess::validate_read_size((super::MAX_CHUNK_BYTES + 1) as i32),
            Err(error) if error.is_invalid_input()
        ));
    }
}
