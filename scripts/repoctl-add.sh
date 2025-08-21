#!/bin/sh
set -euo pipefail
if [ "$#" -lt 2 ]; then
  echo "Usage: $0 REPO_DIR pkg1.pkg.tar.zst [pkg2 ...]"
  exit 2
fi
REPO_DIR="$1"
shift

# add packages to repo using repoctl if available, fall back to repo-add
if command -v repoctl >/dev/null 2>&1; then
  repoctl add "$REPO_DIR" "$@"
else
  # repo-add requires at least one package
  for p in "$@"; do
    # assume repo-add is available
    repo-add "$REPO_DIR/$(basename "$REPO_DIR").db.tar.gz" "$p"
  done
fi

echo "Added $* to $REPO_DIR"
