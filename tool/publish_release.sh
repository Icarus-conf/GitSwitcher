#!/usr/bin/env bash
#
# Publishes built zips to a GitHub release, surviving GitHub's bad moments.
#
# Usage: tool/publish_release.sh TAG FILE...      (needs GH_TOKEN and GH_REPO)
#
# GitHub's release API fails now and then with 500/502/503, sometimes after
# the work actually happened. So every call is retried, and nothing trusts an
# answer: a release "failed to create" may exist, and an upload that "failed"
# may be complete. Each upload is confirmed by comparing the SHA-256 GitHub
# records for the asset with the local file's, and only that counts.
#
# The release is created only if missing, with notes from
# .github/release-notes/TAG.md, or default.md beside it. Notes already on
# GitHub are never overwritten, so editing them there is safe.
#
# ATTEMPTS and DELAY (seconds, multiplied by the attempt number) are for tests.

set -euo pipefail

TAG="$1"
shift
ATTEMPTS="${ATTEMPTS:-6}"
DELAY="${DELAY:-15}"
NOTES_DIR="${NOTES_DIR:-.github/release-notes}"

retry() {
  local n=1
  until "$@"; do
    if ((n >= ATTEMPTS)); then
      echo "::error::gave up after $n attempts: $*"
      return 1
    fi
    echo "::warning::attempt $n failed, retrying in $((DELAY * n))s: $*"
    sleep $((DELAY * n))
    n=$((n + 1))
  done
}

sha256() {
  if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi |
    cut -d' ' -f1
}

# Exit 0 if the release exists, 1 if GitHub says it does not, 2 if GitHub could
# not answer (so the caller retries instead of wrongly creating it).
release_state() {
  local out
  if out=$(gh api "repos/$GH_REPO/releases/tags/$TAG" 2>&1); then return 0; fi
  if grep -q "HTTP 404" <<<"$out"; then return 1; fi
  echo "$out" >&2
  return 2
}

ensure_release() {
  local state=0
  release_state || state=$?
  case $state in
    0) echo "release $TAG exists"; return 0 ;;
    2) return 1 ;; # unknown: retry
  esac

  local notes="$NOTES_DIR/$TAG.md"
  [ -f "$notes" ] || notes="$NOTES_DIR/default.md"
  echo "creating release $TAG with $notes"
  if gh release create "$TAG" --verify-tag --title "GitSwitcher $TAG" --notes-file "$notes"; then
    return 0
  fi
  # The create may have worked despite the error; the next attempt checks.
  return 1
}

# The digest GitHub recorded for an asset, or nothing if it is not there.
remote_digest() {
  gh api "repos/$GH_REPO/releases/tags/$TAG" \
    --jq ".assets[] | select(.name == \"$1\") | .digest // \"\""
}

upload_verified() {
  local file="$1" name want got
  name="$(basename "$file")"
  want="sha256:$(sha256 "$file")"

  # Already there and identical (an earlier attempt that "failed"): done.
  got="$(remote_digest "$name" 2>/dev/null || true)"
  if [ "$got" = "$want" ]; then
    echo "$name: already uploaded and verified"
    return 0
  fi

  gh release upload "$TAG" "$file" --clobber || echo "upload of $name reported an error; checking"
  got="$(remote_digest "$name" 2>/dev/null || true)"
  if [ "$got" = "$want" ]; then
    echo "$name: uploaded and verified ($want)"
    return 0
  fi
  echo "$name: GitHub has '${got:-nothing}', expected $want"
  return 1
}

retry ensure_release
for file in "$@"; do
  retry upload_verified "$file"
done
echo "published $TAG"
