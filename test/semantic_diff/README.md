# Semantic Differential Fixtures

These fixtures compare runtime output between:

1. Haxe reference execution (`--interp`)
2. `reflaxe.rust` portable output (`cargo run` on generated Rust)

Runner:

```bash
python3 test/run-semantic-diff.py
```

Optional case-local Rust defines:

- Add `rust_defines.txt` inside a semantic case directory.
- Each non-empty, non-comment line is appended as `-D <value>` to the Rust compile invocation only.

Goal:

- catch semantic drift where generated Rust behavior diverges from the Haxe baseline
- keep a focused set of high-signal fixtures (nullability, exceptions, dispatch, and core sys behavior)
