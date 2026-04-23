#!/usr/bin/env bash
# TC5: route exists, test file exists, pytest passes.
set -euo pipefail
grep -Eq '@app\.get\("/health"\)' app/main.py || { echo "/health route missing" >&2; exit 1; }
[ -f tests/test_health.py ] || { echo "tests/test_health.py missing" >&2; exit 1; }
.venv/bin/pytest -q >/dev/null 2>&1
