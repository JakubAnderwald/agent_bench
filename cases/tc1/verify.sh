#!/usr/bin/env bash
# TC1 is read-only. Success = no files modified.
set -euo pipefail
# If git sees any diff or new/untracked file (other than nothing), fail.
if [ -n "$(git status --porcelain)" ]; then
  echo "tree was modified:" >&2
  git status --porcelain >&2
  exit 1
fi
exit 0
