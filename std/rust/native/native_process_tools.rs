/// `native_process_tools`
///
/// Typed helper module backing `rust.process.NativeCommands`.
///
/// This module intentionally uses direct `std::process::Command` APIs and owned `Result<_, String>`
/// values so the metal no-hxrt fixture can prove Rust-native command execution without depending on
/// portable `sys.io.Process` runtime handles or Haxe stream wrappers.
#[derive(Debug)]
pub struct NativeCommands;

#[derive(Debug)]
pub struct CommandOutput {
    status_code: i32,
    stdout: Vec<u8>,
    stderr: Vec<u8>,
}

fn command(program: &std::path::PathBuf, args: &Vec<String>) -> std::process::Command {
    let mut command = std::process::Command::new(program);
    for arg in args {
        command.arg(arg.as_str());
    }
    command
}

fn to_command_output(output: std::process::Output) -> CommandOutput {
    CommandOutput {
        status_code: output.status.code().unwrap_or(1),
        stdout: output.stdout,
        stderr: output.stderr,
    }
}

#[allow(non_snake_case)]
impl CommandOutput {
    pub fn statusCode(&self) -> i32 {
        self.status_code
    }

    pub fn stdoutUtf8(&self) -> Result<String, String> {
        String::from_utf8(self.stdout.clone()).map_err(|err| err.to_string())
    }

    pub fn stderrUtf8(&self) -> Result<String, String> {
        String::from_utf8(self.stderr.clone()).map_err(|err| err.to_string())
    }
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

    pub fn outputUtf8(
        program: &std::path::PathBuf,
        args: &Vec<String>,
    ) -> Result<CommandOutput, String> {
        command(program, args)
            .output()
            .map(to_command_output)
            .map_err(|err| err.to_string())
    }
}
