#!/usr/bin/env python3

"""Prove thread registration and EventLoop transitions survive callback unwinding.

Why
---
Spawned threads currently remove their runtime registration only after callbacks return normally,
and repeating events are rescheduled only after every callback returns. A Haxe throw or Rust unwind
can therefore leave a dead thread addressable forever or silently discard a repeating event.

What
----
The contract compiles one portable Haxe program and runs each lifecycle shape in an isolated process
with a hard timeout. It proves dead-thread rejection, repeated cleanup, event-loop-thread cleanup,
repeat rescheduling/cancellation, and balanced promise consumption.

How
---
Every mode is a real generated Rust executable. Expected uncaught child exceptions use one stable
best-effort stderr diagnostic; exceptions caught by Haxe remain silent. A timeout is always failure.
"""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys
import tempfile

from python_tool_commands import project_haxe_command


ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "test" / "runtime_e2e" / "thread_event_loop_lifecycle"
TIMEOUT_SECONDS = 8
UNCAUGHT_PREFIX = "[HXRT-THREAD-UNCAUGHT] "


def run_checked(command: list[str], *, cwd: Path, env: dict[str, str] | None = None) -> None:
    completed = subprocess.run(command, cwd=cwd, env=env, text=True, capture_output=True)
    if completed.returncode != 0:
        output = "\n".join(part for part in (completed.stdout, completed.stderr) if part)
        raise AssertionError(f"command failed ({completed.returncode}): {' '.join(command)}\n{output}")


def assert_mode(executable: Path, mode: str, expected_stdout: str, expected_stderr: str = "") -> None:
    try:
        completed = subprocess.run(
            [str(executable), mode],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=TIMEOUT_SECONDS,
            text=True,
        )
    except subprocess.TimeoutExpired as error:
        raise AssertionError(f"{mode} exceeded the {TIMEOUT_SECONDS}s lifecycle timeout") from error

    if completed.returncode != 0:
        raise AssertionError(
            f"{mode} terminated the process (exit {completed.returncode})\n"
            f"stdout={completed.stdout!r}\nstderr={completed.stderr!r}"
        )

    actual_stdout = completed.stdout.replace("\r\n", "\n")
    actual_stderr = completed.stderr.replace("\r\n", "\n")
    if actual_stdout != expected_stdout:
        raise AssertionError(
            f"{mode} stdout mismatch\nexpected={expected_stdout!r}\nactual={actual_stdout!r}"
        )
    if actual_stderr != expected_stderr:
        raise AssertionError(
            f"{mode} stderr mismatch\nexpected={expected_stderr!r}\nactual={actual_stderr!r}"
        )


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="reflaxe-rust-thread-lifecycle-") as temporary:
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
            "rust_crate=thread_event_loop_lifecycle_contract",
            "-D",
            f"rust_output={generated}",
            "-main",
            "Main",
        ])
        run_checked(haxe_command, cwd=ROOT)

        cargo_env = os.environ.copy()
        cargo_env["CARGO_TARGET_DIR"] = str(target)
        run_checked(
            ["cargo", "build", "-q", "--manifest-path", str(generated / "Cargo.toml")],
            cwd=ROOT,
            env=cargo_env,
        )

        executable = target / "debug" / (
            "thread_event_loop_lifecycle_contract.exe"
            if os.name == "nt"
            else "thread_event_loop_lifecycle_contract"
        )
        if not executable.is_file():
            raise AssertionError(f"generated lifecycle executable is missing: {executable}")

        assert_mode(
            executable,
            "thread-throw-cleanup",
            "thread_started=true\nthread_dead=HXRT-THREAD-NOT-ALIVE\nthread_continued=true\n",
            f"{UNCAUGHT_PREFIX}child_failure\n",
        )
        assert_mode(
            executable,
            "thread-event-loop-throw-cleanup",
            "event_thread_started=true\nevent_thread_dead=HXRT-THREAD-NOT-ALIVE\n"
            "event_thread_continued=true\n",
            f"{UNCAUGHT_PREFIX}event_failure\n",
        )
        assert_mode(
            executable,
            "thread-throw-stress",
            "thread_stress_started=32\nthread_stress_dead=32\n",
            f"{UNCAUGHT_PREFIX}stress_failure\n" * 32,
        )
        assert_mode(
            executable,
            "repeat-throw-reschedule",
            "repeat_first_caught=true\nrepeat_hits=2\nrepeat_second=now\nrepeat_final=never\n",
        )
        assert_mode(
            executable,
            "repeat-cancel-throw-cleanup",
            "repeat_cancel_throw_caught=true\nrepeat_cancel_throw_hits=1\n"
            "repeat_cancel_throw_next=never\n",
        )
        assert_mode(
            executable,
            "repeat-cancel-later-due",
            "repeat_cancel_later_first=1\nrepeat_cancel_later_second=0\n"
            "repeat_cancel_later_progress=now\nrepeat_cancel_later_next=never\n",
        )
        assert_mode(
            executable,
            "promised-underflow",
            "promised_underflow=HXRT-EVENTLOOP-PROMISE-UNDERFLOW\n"
            "promised_underflow_ran=false\npromised_underflow_next=never\n"
            "promised_underflow_continued=true\n",
        )
        assert_mode(
            executable,
            "promised-throw-balance",
            "promised_throw_caught=true\npromised_throw_next=never\n"
            "promised_throw_continued=true\n",
        )

    print("[thread-event-loop-lifecycle] OK")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as error:
        print(f"[thread-event-loop-lifecycle] ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
