#!/usr/bin/env bash
# TC3: formatDate extracted and all 3 call sites updated.
set -euo pipefail

# 1. helper file exists and exports formatDate
[ -f "lib/format.ts" ] || { echo "lib/format.ts missing" >&2; exit 1; }
grep -Eq "export (function|const) formatDate" lib/format.ts || {
  echo "formatDate not exported from lib/format.ts" >&2; exit 1; }

# 2. no toLocaleDateString left in the 3 seeded files
for f in components/note-card.tsx components/activity-row.tsx app/profile/page.tsx; do
  [ -f "$f" ] || { echo "$f missing" >&2; exit 1; }
  if grep -q "toLocaleDateString" "$f"; then
    echo "$f still calls toLocaleDateString directly" >&2
    exit 1
  fi
  grep -q "formatDate" "$f" || {
    echo "$f does not use formatDate" >&2; exit 1; }
done

exit 0
