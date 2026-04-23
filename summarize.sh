#!/usr/bin/env bash
# Read results/runs.csv and print median wall time per (case, agent).
set -euo pipefail
cd "$(dirname "$0")"

CSV=results/runs.csv
[ -f "$CSV" ] || { echo "no $CSV yet" >&2; exit 1; }

python3 - "$CSV" <<'PY'
import csv, sys, statistics as s
from collections import defaultdict

rows = list(csv.DictReader(open(sys.argv[1])))
by = defaultdict(list)
succ = defaultdict(list)
for r in rows:
    k = (r["case"], r["agent"])
    by[k].append(float(r["wall_s"]))
    succ[k].append(int(r["success"]))

cases = sorted({r["case"] for r in rows})
agents = sorted({r["agent"] for r in rows})

def fmt(v): return f"{v:6.2f}s" if v is not None else "   -   "

print()
print(f"{'case':5}  " + "  ".join(f"{a:>20}" for a in agents))
print("-" * (7 + 22 * len(agents)))
for c in cases:
    cells = []
    for a in agents:
        times = by.get((c, a), [])
        ok = succ.get((c, a), [])
        if not times:
            cells.append(f"{'-':>20}")
            continue
        med = s.median(times)
        pass_rate = f"{sum(ok)}/{len(ok)}"
        cells.append(f"{fmt(med)} ({pass_rate:>5})".rjust(20))
    print(f"{c:5}  " + "  ".join(cells))

print()
print("winners per case (median wall, only among agents that passed >=1 trial):")
for c in cases:
    best_a, best_t = None, None
    for a in agents:
        times = by.get((c, a), [])
        ok = succ.get((c, a), [])
        if not times or not any(ok): continue
        med = s.median(times)
        if best_t is None or med < best_t:
            best_a, best_t = a, med
    print(f"  {c}: {best_a or '-'}  ({fmt(best_t) if best_t else '-'})")
PY
