#!/usr/bin/env bash
# TC2: heading text + centering combination on the page. The full-height
# container may live in app/page.tsx or app/layout.tsx (both are valid
# Tailwind patterns for viewport centering), but centering classes must
# appear alongside the heading in app/page.tsx.
set -euo pipefail
F="app/page.tsx"
L="app/layout.tsx"
[ -f "$F" ] || { echo "missing $F" >&2; exit 1; }
grep -q "Speed Test Demo" "$F" || { echo "heading text not found" >&2; exit 1; }
# full-height container: accept in page.tsx OR layout.tsx (or html/body full-height classes there).
if ! grep -Eq "min-h-screen|h-screen|h-dvh|min-h-dvh" "$F" \
   && ! { [ -f "$L" ] && grep -Eq "min-h-screen|h-screen|h-dvh|min-h-dvh|h-full|min-h-full" "$L"; }; then
  echo "no full-height container class in page.tsx or layout.tsx" >&2; exit 1
fi
# accept either flex (items-center + justify-center) or grid (place-items-center) in page.tsx.
if ! grep -Eq "items-center|place-items-center" "$F" \
   || ! grep -Eq "justify-center|place-items-center" "$F"; then
  echo "no centering classes" >&2; exit 1
fi
exit 0
