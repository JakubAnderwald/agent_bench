#!/usr/bin/env bash
# TC5: add an endpoint + test to a FastAPI mini-app.
set -euo pipefail
WORKDIR="$1"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
tar xzf "$ROOT/templates/tc5-fastapi.tar.gz" -C "$WORKDIR"
(cd "$WORKDIR" && git init -q && git add -A && git commit -qm seed)
