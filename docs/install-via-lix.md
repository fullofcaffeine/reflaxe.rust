# Install via lix (GitHub-only, Stable 1.x)

This project is distributed via **GitHub Releases** and installed via **lix**.

Current public packaging posture:

- stable release line: `1.x`
- install source: GitHub release tags
- no haxelib.org publish required

The release artifact is haxelib-shaped because Reflaxe/Haxe tooling expects that layout. That does
not mean this repo currently publishes to haxelib.org.

## Prereqs

- Node.js/npm, for `lix` and project scripts.
- Haxe 4.3.7, installed through `lix` below.
- Rust toolchain with `cargo`.
- Git, if installing directly from a GitHub release tag.

## Path 1: Install In An App With lix

Use this when you are consuming `reflaxe.rust` from another Haxe project.

```bash
# Create a lix scope in your project directory
npx lix scope create

# Install a specific release tag (recommended)
# Pick a tag from the Releases page if you prefer.
REFLAXE_RUST_TAG="$(curl -fsSL https://api.github.com/repos/fullofcaffeine/reflaxe.rust/releases/latest | sed -n 's/.*\"tag_name\":[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p' | head -n 1)"
npx lix install "github:fullofcaffeine/reflaxe.rust#${REFLAXE_RUST_TAG}"

# Download pinned libs (reflaxe + deps)
npx lix download

# Pin Haxe (recommended; this target is built for Haxe 4.3.7)
npx lix download haxe 4.3.7
npx lix use haxe 4.3.7
```

Then add `-lib reflaxe.rust` and a Rust output directory to your app HXML.

## Minimal `compile.hxml`

```hxml
-cp src
-lib reflaxe.rust

-D rust_output=out
-D rust_crate=my_app

--main Main
```

Then:

```bash
haxe compile.hxml
(cd out && cargo run)
```

## Path 2: Scaffold A Starter App From This Repo

Use this when you are evaluating the target from a local checkout and want the recommended project
layout, `cargo hx` task driver, watch script, and guard scripts generated for you.

```bash
npm install
npm run dev:new-project -- ./my_haxe_rust_app
cd my_haxe_rust_app
```

Install the release dependency inside the generated app:

```bash
npx lix scope create
REFLAXE_RUST_TAG="$(curl -fsSL https://api.github.com/repos/fullofcaffeine/reflaxe.rust/releases/latest | sed -n 's/.*\"tag_name\":[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p' | head -n 1)"
npx lix install "github:fullofcaffeine/reflaxe.rust#${REFLAXE_RUST_TAG}"
npx lix download
npx lix download haxe 4.3.7
npx lix use haxe 4.3.7
```

Run the generated project:

```bash
cargo hx --action run
cargo hx --action test
cargo hx --action build --release
```

The generated README documents the same commands plus watch mode, guards, and pre-commit setup.

## Path 3: Work On This Compiler Locally

Use this when contributing to `reflaxe.rust` itself.

```bash
npm install
npm test
npm run test:all
```

For the full local CI-equivalent run:

```bash
bash scripts/ci/local.sh
```

## Production Checklist After Install

Before using a generated or existing app in production:

1. Keep `portable` as the default profile unless a path has a measured Rust-first need.
2. Pin the release tag and commit the generated lockfiles.
3. Use locked Cargo builds in CI when practical (`-D rust_cargo_locked`).
4. Add smoke tests for the specific file/process/network/TLS/DB/thread behavior your app uses.
5. Keep native Rust interop behind typed wrappers.

See [Production Readiness](production-readiness.md) and the [Feature support matrix](feature-support-matrix.md)
for the current evidence-backed contract boundaries.

## Troubleshooting

- If `haxe compile.hxml` cannot find `reflaxe.rust`, run `npx lix download` again and confirm the
  project has a lix scope.
- If Cargo cannot find dependencies, run the generated command from the project root so `out/` and
  `Cargo.toml` resolve relative paths correctly.
- If you need to verify the packaged artifact itself, use the repo smoke guard:
  `bash scripts/ci/package-smoke.sh`.
