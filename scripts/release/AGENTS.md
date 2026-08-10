# Release-tooling agent notes

- Release provenance means “the bytes in the named Git commit,” not “whatever a clean worktree
  currently returns.” `assume-unchanged`, `skip-worktree`, checkout filters, and line-ending settings
  can all make those differ without appearing in ordinary status output.
- Release and repair workflows must first extract `exact-git-source.js` directly from the named Git
  object with replacement objects and local/global Git configuration disabled. That external copy
  materializes the repository and rechecks every tracked byte after tool installation, before any
  repository-owned release entrypoint is loaded.
- Preparation, publication, repair, and verification use `reviewed-source.js` to materialize every
  rebuild from literal `sourceCommit` blobs. Do not restore live-worktree builds as an optimization.
  A standalone verifier is authoritative only when it runs inside a repository carrying the matching
  external-bootstrap receipt; live code cannot authenticate its own pre-execution bytes.
- `env -i` removes GitHub Actions' step files too. A release step that asks a reviewed script to
  write `--github-output` or activate a toolchain must pass the exact runner-provided `GITHUB_ENV`
  and `GITHUB_OUTPUT` paths explicitly; otherwise the sanitized job fails before setup.
- Semantic-release 25 uses singular `GITHUB_ACTION` to recognize GitHub Actions installation-token
  Git authentication. Keep that marker, together with the reviewed token, in the final allowlist;
  `GITHUB_ACTIONS` alone identifies CI but does not select the `x-access-token:` credential form.
- Repair input is an exact stable tag, never a convenient short ref. Validate `vMAJOR.MINOR.PATCH`
  before checkout, check out `refs/tags/<tag>`, resolve that full namespace again, and require HEAD
  to equal the tag commit before any code from the repaired revision runs.
- Treat `origin` as the tag authority during bootstrap. Record its complete tag snapshot, reject
  local-only or stale tags later, and permit only the single newly derived stable tag at the reviewed
  commit. Semantic-release's broad `git push --tags` must pass through the reviewed guard that
  publishes only that approved ref.
- Host controls are preconditions, but GitHub's short-lived Actions token cannot read the
  repository-administration immutable-Releases endpoint. Immediately before a write-capable release
  command, use that token to verify the publicly readable version-tag update/deletion ruleset. Then
  re-read and validate the exact mutable, non-prerelease draft and receipt-bound asset set before
  changing the draft to public, and require the published Release itself to report immutable.
  `verify-host-controls.js` remains a maintainer audit that deliberately requires repository-
  administration read access; never call it from the ordinary release or repair token.
- Two reproducible builds are useful only when their inputs independently come from the reviewed
  commit. Comparing two packages built from the same live checkout is not source evidence.
- Artifact construction and verification may use Node built-ins, but must not load executable package
  logic from `node_modules`. Release orchestration still uses locked semantic-release dependencies;
  clear shell/Node injection variables before that boundary and recheck tracked bytes afterward.
- Clearing `BASH_ENV` or `NODE_OPTIONS` inside a script is too late for the interpreter that started
  it. Privileged workflow steps use profile-free absolute Bash with startup variables cleared at the
  job boundary, absolute setup-node/Git paths, strict object validation, and a freshly extracted final
  checker after dependency setup.
- A Git object pathname is not proof of its content. Keep strict reachable-object `fsck`, independent
  blob hashing, complete stage-0 index comparison, fixed empty hooks, fixed config, and rejected
  alternates together; weakening one reopens a same-wrong-source path.
- Do not execute Cargo to discover the unresolved requirements already written in `Cargo.toml`.
  License/SBOM generation uses the source-owned fail-closed manifest projection, while real Cargo is
  reserved for the later build/run observer under its exact tool path and fresh Cargo home.
  Reject path, Git, registry, workspace-inherited, patch, replace, and unknown dependency selectors;
  silently dropping a source selector would misstate where a shipped requirement comes from.
- Lix shims need the cache in their configured HOME. Install into one fresh job-owned Lix home, copy
  the reviewed project `.haxerc` to its global `haxe/.haxerc`, and reuse that isolated home during
  release execution. Switching to a second empty home makes temporary package directories resolve or
  download the mutable `stable` alias; switching to the runner home reintroduces ambient state.
- The package smoke intentionally has two library authorities. The installed-package compile uses its
  temporary `haxelib newrepo` plus a temporary exact-version `.haxerc` with `resolveLibs: "haxelib"`;
  the source-layout compile sets `HAXE_LIBRARY_PATH` to the exact repository `haxe_libraries`
  directory. Keep those authorities local to their compile—sharing either one would let a smoke half
  pass against the wrong source.
- Artifact approval is a captured receipt, not a later digest of whatever remains in `dist/`.
  Keep the normal-release receipt in process memory rather than writable repository storage. Normal
  publication and repair must check upload copies and hosted API identities against that same receipt;
  no intervening general publisher may own those paths.
- Required Haxe and Reflaxe license bytes have fixed code-owned files. Extra component license text is
  inline in the tracked component record; do not add editable filesystem pointers as a convenience.
- Every repository-sized Git query must set the shared explicit output bound. Tests must distinguish a
  controlled dirty-tree rejection from an `ENOBUFS` process failure.
