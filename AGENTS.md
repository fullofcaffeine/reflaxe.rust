# AI/Agent Instructions for `reflaxe.rust`

## Issue Tracking

This project uses **bd (beads)** for issue tracking.

- `bd prime` — workflow context
- `bd ready` — unblocked work
- `bd show <id>` — details
- `bd update <id> --status in_progress` — claim
- `bd close <id>` — complete
- `bd sync` — sync to git (once a remote is configured)

Milestone plan lives in Beads under epic `haxe.rust-oo3` (see `bd graph haxe.rust-oo3 --compact`).

## Product Source of Truth

- Requirements + architecture: `prd.md`
- Target: **Haxe 4.3.7 → Rust** via Reflaxe

## Core Guardrails (compiler)

- Keep the pipeline **AST-first**: Builder → Transformer passes → Printer (avoid string-gen except at the printer).
- Prefer typed analysis + passes over regex/string heuristics.
- Portable mode first; keep a single runtime abstraction point so backends can evolve (e.g., `HxRef<T>`).

## Important Lessons (POC)

- Reflaxe’s `Context.getMainExpr()` is only reliable when the consumer uses `-main <Class>` (don’t rely on a bare trailing `Main` line in `.hxml`).
- Use `BaseCompiler.setExtraFile()` for non-`.rs` outputs like `Cargo.toml` (the default OutputManager always appends `fileOutputExtension` for normal outputs).
- Haxe “multi-type modules” behave like `haxe.macro.Expr.*`: types in `RustAST.hx` are addressed as `RustAST.RustExpr`, `RustAST.RustFile`, etc.
- Keep generated Rust rustfmt-clean: avoid embedding extra trailing newlines in raw items and always end files with a final newline.
- For class instance semantics, the current POC uses `type HxRef<T> = Rc<RefCell<T>>` and lowers method calls as `Class::method(&obj, ...)`.
- For field assignment on `HxRef` (`obj.field = rhs`), evaluate `rhs` first, then take `borrow_mut()` (otherwise `RefCell` will panic at runtime when `rhs` reads other fields).
- For void Haxe functions, don’t emit a tail expression just because the last expression has a non-void type (e.g. `OpAssign` is typed as the RHS); pass the expected return type into block compilation to decide whether a tail is allowed.
- `bd create` is unreliable in this repo’s current beads setup; use `bd q` + `bd update` to create structured issues.

## Testing + CI

- Run snapshots locally: `bash test/run-snapshots.sh`
- Update a snapshot’s golden output (after review): `bash test/run-snapshots.sh --case <name> --update`
- CI runs:
  - `test/run-snapshots.sh` (includes `cargo fmt -- --check` + `cargo build -q` per snapshot)
  - example smoke runs (`examples/hello`, `examples/classes`)

## Releases

- GitHub Actions:
  - `.github/workflows/ci.yml` runs on PRs/pushes to `main`.
  - `.github/workflows/release.yml` runs on tags `v*` and publishes a GitHub Release with a haxelib zip.
- Tag/version policy: tag `vX.Y.Z` must match `haxelib.json` `"version": "X.Y.Z"`.
- Package locally: `bash scripts/release/package-haxelib.sh dist/reflaxe.rust.zip`
- Optional: set `HAXELIB_PASSWORD` secret to auto-publish to haxelib on tag releases.
