#!/usr/bin/env bash
# TC4: tests pass AND test/ unchanged.
set -euo pipefail
# test files must not have been touched
if ! git diff --quiet HEAD -- test/ 2>/dev/null; then
  echo "test/ was modified" >&2
  git diff --name-only HEAD -- test/ >&2
  exit 1
fi
npm test --silent >/dev/null 2>&1
