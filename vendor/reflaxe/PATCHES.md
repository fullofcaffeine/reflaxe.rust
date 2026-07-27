# Vendored Reflaxe changes

This directory starts from the exact Reflaxe commit recorded in
[provenance.json](provenance.json) and includes a reviewed set of
haxe.rust-specific framework changes.

The exact source diff is [reflaxe-rust.patch](reflaxe-rust.patch). The
machine-readable [provenance record](provenance.json) names the upstream
repository and base commit, lists every changed source file, records the last
upstream revision checked, and names the tests that cover the shipped result.
Run:

```sh
node scripts/ci/vendor-reflaxe-provenance.js
node scripts/ci/vendor-reflaxe-provenance.js --upstream-dir /path/to/reflaxe
```

The first command catches a stale patch or file list. The second reconstructs
the vendored source from a real upstream checkout and proves that the patch
produces the files shipped here.

## What changed and why

The local changes add the typed hooks and deterministic output behavior needed
by the Rust compiler. They cover compiler initialization, module and type-use
tracking, target-code injection, expression preprocessing, and output
registration. Keeping the complete diff is important: a short prose summary
cannot prove which code is actually shipped.

The previous version of this document described a speculative EReg filesystem
bug from the Reflaxe.Elixir project. That explanation did not describe the
haxe.rust vendor tree and has been removed.

## Upstream status

The current upstream review status and the last upstream revision checked are
recorded once in [provenance.json](provenance.json).

Do not remove a local change merely because a related upstream pull request
merged. First update the recorded base, regenerate the exact patch, and run the
full compiler and package tests.

## License

Reflaxe is provided under the MIT license. The exact upstream license text is
included as [LICENSE](LICENSE) and is also shipped in the haxe.rust release
package. This is a factual inventory, not legal advice; unresolved release
licensing questions are listed in `docs/release-licensing-review.md`.
