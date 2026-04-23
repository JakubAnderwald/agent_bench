#!/usr/bin/env bash
# TC6 is read-only. Success = tree unchanged.
set -euo pipefail
if [ -n "$(git status --porcelain)" ]; then
  echo "tree was modified:" >&2
  git status --porcelain >&2
  exit 1
fi
exit 0
