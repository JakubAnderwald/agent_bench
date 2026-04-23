#!/usr/bin/env bash
# TC1: exploration, read-only. Copy a clean `ky` checkout into the workdir.
set -euo pipefail
WORKDIR="$1"
REPO="$(cd "$(dirname "$0")/../.." && pwd)/repos/ky"
[ -d "$REPO" ] || { echo "repos/ky missing — run ./prepare.sh" >&2; exit 1; }
# hardlink-copy, then seed git so the agent can see a clean tree
cp -R "$REPO/." "$WORKDIR/"
(cd "$WORKDIR" && rm -rf .git && git init -q && git add -A && git commit -qm seed)
