#!/usr/bin/env bash
# TC6: large-repo read, clean express checkout.
set -euo pipefail
WORKDIR="$1"
REPO="$(cd "$(dirname "$0")/../.." && pwd)/repos/express"
[ -d "$REPO" ] || { echo "repos/express missing — run ./prepare.sh" >&2; exit 1; }
cp -R "$REPO/." "$WORKDIR/"
(cd "$WORKDIR" && rm -rf .git && git init -q && git add -A && git commit -qm seed)
