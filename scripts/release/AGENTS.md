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
- Two reproducible builds are useful only when their inputs independently come from the reviewed
  commit. Comparing two packages built from the same live checkout is not source evidence.
- Artifact construction and verification may use Node built-ins, but must not load executable package
  logic from `node_modules`. Release orchestration still uses locked semantic-release dependencies;
  clear shell/Node injection variables before that boundary and recheck tracked bytes afterward.
- Required Haxe and Reflaxe license bytes have fixed code-owned files. Extra component license text is
  inline in the tracked component record; do not add editable filesystem pointers as a convenience.
- Every repository-sized Git query must set the shared explicit output bound. Tests must distinguish a
  controlled dirty-tree rejection from an `ENOBUFS` process failure.
