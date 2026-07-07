/// `native_process_tools`
///
/// Typed helper module backing `rust.process.NativeCommands`.
///
/// This module intentionally uses direct `std::process::Command` APIs and owned `Result<_, String>`
/// values so the metal no-hxrt fixture can prove Rust-native command execution without depending on
/// portable `sys.io.Process` runtime handles or Haxe stream wrappers.
#[derive(Debug)]
pub struct NativeCommands;

fn command(program: &std::path::PathBuf, args: &Vec<String>) -> std::process::Command {
    let mut command = std::process::Command::new(program);
    for arg in args {
        command.arg(arg.as_str());
    }
    command
}

#[allow(non_snake_case)]
impl NativeCommands {
    pub fn statusCode(program: &std::path::PathBuf, args: &Vec<String>) -> Result<i32, String> {
        let mut command = command(program, args);
        command
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status()
            .map(|status| status.code().unwrap_or(1))
            .map_err(|err| err.to_string())
    }

    pub fn stdoutUtf8(program: &std::path::PathBuf, args: &Vec<String>) -> Result<String, String> {
        let output = command(program, args)
            .output()
            .map_err(|err| err.to_string())?;
        String::from_utf8(output.stdout).map_err(|err| err.to_string())
    }
}
