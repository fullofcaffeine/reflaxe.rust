# Install via lix (GitHub-only)

This project is currently distributed via **GitHub releases** and installed via **lix** (no haxelib publish required).

## Prereqs

- Node.js (for lix)
- Rust toolchain (`cargo`)

## Install

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

