#!/usr/bin/env python3

"""Exercise portable Sys/std-stream failures at real process boundaries.

Why
---
Rust `unwrap()` panics and discarded `std::io::Error` values can look correct on happy paths while
making normal Haxe failures uncatchable. A subprocess is required to distinguish a Haxe exception
from process termination and to provide genuinely invalid stdin/stdout descriptors.

What
----
The contract builds one generated portable crate and proves that a closed stdout pipe throws typed
`haxe.io.Error`, an invalid stdin descriptor is not mistaken for EOF, real EOF remains `Eof`, and
the deliberately non-admitted `Sys.cpuTime` surface fails explicitly instead of returning wall time.

How
---
On POSIX, the child receives a pipe end that cannot perform the requested operation. The program
catches the failure and writes its continuation marker through the unaffected standard stream.
The CPU-time disposition check is platform-independent.
"""

from __future__ import annotations

import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

from python_tool_commands import project_haxe_command


ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "test" / "runtime_e2e" / "portable_sys_failures"


def run_checked(command: list[str], *, cwd: Path, env: dict[str, str] | None = None) -> None:
    completed = subprocess.run(command, cwd=cwd, env=env, text=True, capture_output=True)
    if completed.returncode != 0:
        output = "\n".join(part for part in (completed.stdout, completed.stderr) if part)
        raise AssertionError(f"command failed ({completed.returncode}): {' '.join(command)}\n{output}")


def assert_process(label: str, completed: subprocess.CompletedProcess[bytes], expected: str, stream: str) -> None:
    if completed.returncode != 0:
        raise AssertionError(
            f"{label} terminated instead of returning through Haxe catch (exit {completed.returncode})\n"
            f"stdout={completed.stdout!r}\nstderr={completed.stderr!r}"
        )
    actual_bytes = completed.stderr if stream == "stderr" else completed.stdout
    actual = actual_bytes.decode("utf-8").replace("\r\n", "\n")
    if actual != expected:
        raise AssertionError(f"{label} {stream} mismatch\nexpected={expected!r}\nactual={actual!r}")


def run_with_closed_pipe(executable: Path, mode: str, broken_stream: str) -> subprocess.CompletedProcess[bytes]:
    read_fd, write_fd = os.pipe()
    os.close(read_fd)
    options: dict[str, object] = {
        "stdin": subprocess.DEVNULL,
        "stdout": subprocess.PIPE,
        "stderr": subprocess.PIPE,
    }
    options[broken_stream] = write_fd
    try:
        process = subprocess.Popen([str(executable), mode], **options)
        stdout, stderr = process.communicate(timeout=30)
        return subprocess.CompletedProcess(
            process.args,
            process.returncode,
            stdout if stdout is not None else b"",
            stderr if stderr is not None else b"",
        )
    finally:
        os.close(write_fd)


def main() -> int:
    runtime_source = (ROOT / "runtime" / "hxrt" / "src" / "sys.rs").read_text(encoding="utf-8")
    for banned in (r"\.unwrap\(", r"\.ok\(\)"):
        if re.search(banned, runtime_source):
            raise AssertionError(f"portable Sys runtime contains a normal-failure bypass matching {banned}")

    with tempfile.TemporaryDirectory(prefix="reflaxe-rust-portable-sys-") as temporary:
        temp_root = Path(temporary)
        generated = temp_root / "generated"
        target = temp_root / "target"
        haxe_command = project_haxe_command(ROOT, [
            "-cp",
            str(FIXTURE),
            "-lib",
            "reflaxe.rust",
            "-D",
            "reflaxe_rust_profile=portable",
            "-D",
            "reflaxe_rust_strict_examples",
            "-D",
            "rust_no_build",
            "-D",
            "rust_crate=portable_sys_failure_contract",
            "-D",
            f"rust_output={generated}",
            "-main",
            "Main",
        ])
        run_checked(haxe_command, cwd=ROOT)

        cargo_env = os.environ.copy()
        cargo_env["CARGO_TARGET_DIR"] = str(target)
        run_checked(["cargo", "build", "-q", "--manifest-path", str(generated / "Cargo.toml")], cwd=ROOT, env=cargo_env)

        executable = target / "debug" / ("portable_sys_failure_contract.exe" if os.name == "nt" else "portable_sys_failure_contract")
        if not executable.is_file():
            raise AssertionError(f"generated failure-contract executable is missing: {executable}")

        cpu = subprocess.run([str(executable), "cpu-time"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert_process("cpu-time disposition", cpu, "cpu_time=experimental\ncpu_time_continued=true\n", "stdout")

        missing_command = subprocess.run(
            [str(executable), "missing-command"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        assert_process(
            "missing direct command",
            missing_command,
            "missing_direct_command=caught\nmissing_direct_command_continued=true\n",
            "stdout",
        )

        invalid_env = subprocess.run(
            [str(executable), "invalid-env"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        assert_process(
            "invalid environment name",
            invalid_env,
            "invalid_get_env=caught\ninvalid_get_env_continued=true\n"
            "invalid_put_env=caught\ninvalid_put_env_continued=true\n"
            "invalid_put_env_value=caught\ninvalid_put_env_value_continued=true\n",
            "stdout",
        )

        if os.name == "posix":
            assert_process(
                "broken stdout",
                run_with_closed_pipe(executable, "broken-stdout", "stdout"),
                "broken_stdout=io_error\nbroken_stdout_continued=true\n",
                "stderr",
            )
            assert_process(
                "broken Sys.print",
                run_with_closed_pipe(executable, "broken-sys-print", "stdout"),
                "broken_sys_print=io_error\nbroken_sys_print_continued=true\n",
                "stderr",
            )
            assert_process(
                "broken stderr",
                run_with_closed_pipe(executable, "broken-stderr", "stderr"),
                "broken_stderr=io_error\nbroken_stderr_continued=true\n",
                "stdout",
            )

            invalid_stdin_fd = os.open(os.path.abspath(os.sep), os.O_RDONLY)
            try:
                invalid_stdin = subprocess.Popen(
                    [str(executable), "stdin-error"],
                    stdin=invalid_stdin_fd,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                )
                invalid_stdout, invalid_stderr = invalid_stdin.communicate(timeout=30)
                invalid_result = subprocess.CompletedProcess(
                    invalid_stdin.args, invalid_stdin.returncode, invalid_stdout, invalid_stderr
                )
            finally:
                os.close(invalid_stdin_fd)
            assert_process(
                "invalid stdin",
                invalid_result,
                "stdin_error=io_error\nstdin_error_continued=true\n",
                "stdout",
            )

            eof = subprocess.run(
                [str(executable), "stdin-eof"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            assert_process("stdin EOF", eof, "stdin_eof=eof\nstdin_eof_continued=true\n", "stdout")
        else:
            print("[portable-sys-failures] POSIX descriptor cases skipped on this host")

    print("[portable-sys-failures] OK")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, subprocess.TimeoutExpired) as error:
        print(f"[portable-sys-failures] ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
