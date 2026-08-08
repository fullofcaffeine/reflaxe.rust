#!/usr/bin/env bash
set -euo pipefail

# Why: semantic-release's pinned Git core publishes every local tag with `git push --tags`.
# Local tag refs are mutable checkout state, so that broad command can publish a tag that was never
# derived or approved by this release. What: replace only that exact broad push with the single
# approved release ref. How: verify its stable-version spelling and commit target, then delegate all
# other Git behavior to the absolute reviewed executable with replacement objects disabled.
: "${RELEASE_GIT_BIN:?release Git guard requires RELEASE_GIT_BIN}"
if [[ ! "$RELEASE_GIT_BIN" = /* || ! -x "$RELEASE_GIT_BIN" ]]; then
  echo "RELEASE_GIT_BIN must be an absolute executable" >&2
  exit 1
fi

if [[ "${1:-}" == push && "${2:-}" == --tags && $# -eq 3 ]]; then
  tag="${RELEASE_APPROVED_TAG:-}"
  source_commit="${RELEASE_SOURCE_COMMIT:-}"
  if [[ ! "$tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    echo "release Git guard requires an exact approved stable-version tag" >&2
    exit 1
  fi
  if [[ ! "$source_commit" =~ ^[0-9a-f]{40}$ ]]; then
    echo "release Git guard requires the exact approved source commit" >&2
    exit 1
  fi
  local_commit="$("$RELEASE_GIT_BIN" --no-replace-objects rev-parse --verify "refs/tags/$tag^{commit}")"
  if [[ "$local_commit" != "$source_commit" ]]; then
    echo "approved release tag does not identify the approved source commit" >&2
    exit 1
  fi
  exec "$RELEASE_GIT_BIN" --no-replace-objects push --no-verify "$3" \
    "refs/tags/$tag:refs/tags/$tag"
fi

exec "$RELEASE_GIT_BIN" --no-replace-objects "$@"
