#[derive(Debug)]
pub struct SocketError {
    kind: SocketErrorKind,
    message: String,
}

#[derive(Debug)]
enum SocketErrorKind {
    InvalidInput,
    Io,
    Utf8,
}

#[allow(non_snake_case)]
impl SocketError {
    pub(crate) fn invalid_input(message: String) -> SocketError {
        SocketError {
            kind: SocketErrorKind::InvalidInput,
            message,
        }
    }

    pub(crate) fn io(error: std::io::Error) -> SocketError {
        SocketError {
            kind: SocketErrorKind::Io,
            message: error.to_string(),
        }
    }

    pub(crate) fn utf8(error: std::string::FromUtf8Error) -> SocketError {
        SocketError {
            kind: SocketErrorKind::Utf8,
            message: error.to_string(),
        }
    }

    pub fn message(&self) -> String {
        self.message.clone()
    }

    pub fn isInvalidInput(&self) -> bool {
        matches!(self.kind, SocketErrorKind::InvalidInput)
    }

    pub fn isIo(&self) -> bool {
        matches!(self.kind, SocketErrorKind::Io)
    }

    pub fn isUtf8(&self) -> bool {
        matches!(self.kind, SocketErrorKind::Utf8)
    }
}
