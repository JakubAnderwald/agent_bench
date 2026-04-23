#!/usr/bin/env bash
# TC2: small localised edit on a fresh Next.js app.
set -euo pipefail
WORKDIR="$1"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
tar xzf "$ROOT/templates/nextjs.tar.gz" -C "$WORKDIR"
(cd "$WORKDIR" && git init -q && git add -A && git commit -qm seed)
