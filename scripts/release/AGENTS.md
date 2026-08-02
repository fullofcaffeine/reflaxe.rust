# Release-tooling agent notes

- Release provenance means “the bytes in the named Git commit,” not “whatever a clean worktree
  currently returns.” `assume-unchanged`, `skip-worktree`, checkout filters, and line-ending settings
  can all make those differ without appearing in ordinary status output.
- Preparation, publication, repair, and standalone verification must use
  `reviewed-source.js` to materialize `sourceCommit`. Run the package transformation, repository-owned
  generators, and strict verifier from that materialized tree. Do not restore live-worktree builds as
  an optimization.
- Two reproducible builds are useful only when their inputs independently come from the reviewed
  commit. Comparing two packages built from the same live checkout is not source evidence.
- Required Haxe and Reflaxe license bytes have fixed code-owned files. Extra component license text is
  inline in the tracked component record; do not add editable filesystem pointers as a convenience.
- Every repository-sized Git query must set the shared explicit output bound. Tests must distinguish a
  controlled dirty-tree rejection from an `ENOBUFS` process failure.
