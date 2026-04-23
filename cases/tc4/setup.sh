#!/usr/bin/env bash
# TC4: bugfix from failing tests.
set -euo pipefail
WORKDIR="$1"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
tar xzf "$ROOT/templates/tc4-bugfix.tar.gz" -C "$WORKDIR"
(cd "$WORKDIR" && git init -q && git add -A && git commit -qm seed)
