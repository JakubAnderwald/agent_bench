#!/usr/bin/env bash
# Parse results/raw/**/stream.jsonl into results/metrics.csv and print a
# rich summary: median output tok/s, cache-hit %, tool-time %, $/run.
#
# Safe to re-run; overwrites results/metrics.csv from the existing raw streams.
# Token/cost columns are only populated for the two claude-* agents; copilot
# streams don't expose token counts.
set -euo pipefail
cd "$(dirname "$0")"

RAW=results/raw
RUNS=results/runs.csv
OUT=results/metrics.csv

[ -d "$RAW" ] || { echo "no $RAW yet; run ./bench.sh first" >&2; exit 1; }
[ -f "$RUNS" ] || { echo "no $RUNS yet; run ./bench.sh first" >&2; exit 1; }

python3 - "$RAW" "$RUNS" "$OUT" <<'PY'
import csv, json, os, sys, statistics as stat
from collections import defaultdict
from pathlib import Path

raw_dir, runs_csv, out_csv = sys.argv[1], sys.argv[2], sys.argv[3]

def last_result(path):
    """Return the final {'type':'result',...} event from a JSONL stream, or None."""
    found = None
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line or '"type":"result"' not in line:
                    continue
                try:
                    d = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if d.get("type") == "result":
                    found = d
    except FileNotFoundError:
        pass
    return found

def parse_claude(r):
    u = r.get("usage", {}) or {}
    return {
        "api_s":         (r.get("duration_api_ms") or 0) / 1000.0 or None,
        "input_tokens":  u.get("input_tokens"),
        "output_tokens": u.get("output_tokens"),
        "cache_read":    u.get("cache_read_input_tokens"),
        "cache_created": u.get("cache_creation_input_tokens"),
        "cost_usd":      r.get("total_cost_usd"),
        "lines_changed": None,  # claude stream doesn't report this
    }

def parse_copilot(r):
    u = r.get("usage", {}) or {}
    cc = u.get("codeChanges", {}) or {}
    lines = (cc.get("linesAdded") or 0) + (cc.get("linesRemoved") or 0)
    return {
        "api_s":         (u.get("totalApiDurationMs") or 0) / 1000.0 or None,
        "input_tokens":  None,
        "output_tokens": None,
        "cache_read":    None,
        "cache_created": None,
        "cost_usd":      None,
        "lines_changed": lines if cc else None,
    }

# Join the externally-measured wall_s / success / turns / tool_calls from
# runs.csv with the richer fields from stream.jsonl.
#
# A pre-fix bench.sh run under a non-C locale writes `wall_s` as e.g. `54,47`,
# which csv.reader splits into two cells. Detect that and rejoin: if a row has
# 8 fields instead of 7, the 4th and 5th are the wall_s halves.
runs = []
with open(runs_csv) as f:
    reader = csv.reader(f)
    header = next(reader)
    expected = len(header)
    for raw in reader:
        if len(raw) == expected + 1:
            raw = raw[:3] + [f"{raw[3]}.{raw[4]}"] + raw[5:]
        if len(raw) != expected:
            continue  # malformed row; skip
        runs.append(dict(zip(header, raw)))

cols = ["trial","case","agent","wall_s","success","turns","tool_calls",
        "api_s","input_tokens","output_tokens","cache_read","cache_created",
        "cost_usd","lines_changed"]

rows = []
for r in runs:
    stream = Path(raw_dir) / f"t{r['trial']}" / r["case"] / r["agent"] / "stream.jsonl"
    res = last_result(stream)
    extra = {k: None for k in cols if k not in r}
    if res:
        if r["agent"].startswith("claude"):
            extra.update(parse_claude(res))
        elif r["agent"] == "copilot":
            extra.update(parse_copilot(res))
    rows.append({**r, **extra})

with open(out_csv, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=cols)
    w.writeheader()
    for row in rows:
        w.writerow({k: row.get(k, "") if row.get(k) is not None else "" for k in cols})

print(f"wrote {out_csv}  ({len(rows)} rows)")

# --- summary ------------------------------------------------------------
def med(xs):
    xs = [x for x in xs if x is not None]
    return stat.median(xs) if xs else None

by = defaultdict(list)
for row in rows:
    by[(row["case"], row["agent"])].append(row)

cases  = sorted({r["case"]  for r in rows})
agents = sorted({r["agent"] for r in rows})

def num(row, k):
    v = row.get(k)
    if v in (None, "", "None"): return None
    try: return float(v)
    except ValueError: return None

def tok_per_s(row):
    out = num(row, "output_tokens"); api = num(row, "api_s")
    return (out / api) if out and api else None

def cache_hit(row):
    r  = num(row, "cache_read")  or 0
    cc = num(row, "cache_created") or 0
    i  = num(row, "input_tokens") or 0
    total = r + cc + i
    return (r / total) if total else None

def tool_share(row):
    wall = num(row, "wall_s"); api = num(row, "api_s")
    if not wall or not api: return None
    # api can exceed wall on retries/overlapping streams; clamp.
    return max(0.0, min(1.0, 1 - (api / wall)))

def fmt_s(v):   return f"{v:6.2f}s"  if v is not None else "    -  "
def fmt_tok(v): return f"{v:5.0f}"   if v is not None else "  -  "
def fmt_pct(v): return f"{v*100:4.0f}%" if v is not None else "  -  "
def fmt_usd(v): return f"${v:5.3f}" if v is not None else "   -  "

def table(title, cell_fn, width=22):
    print()
    print(title)
    print(f"{'case':5}  " + "  ".join(f"{a:>{width}}" for a in agents))
    print("-" * (7 + (width + 2) * len(agents)))
    for c in cases:
        cells = []
        for a in agents:
            cells.append(cell_fn(by.get((c, a), [])).rjust(width))
        print(f"{c:5}  " + "  ".join(cells))

table("median wall time (s)",
      lambda rs: fmt_s(med([num(r,"wall_s") for r in rs])))

table("median API time (s)  [LLM only, tool time excluded]",
      lambda rs: fmt_s(med([num(r,"api_s") for r in rs])))

table("median output tok/s  [output_tokens / api_s; claude only]",
      lambda rs: fmt_tok(med([tok_per_s(r) for r in rs])))

table("median output tokens per run  [claude only]",
      lambda rs: fmt_tok(med([num(r,"output_tokens") for r in rs])))

table("cache hit rate  [cache_read / (cache_read+created+input); claude only]",
      lambda rs: fmt_pct(med([cache_hit(r) for r in rs])))

table("tool-time share of wall  [1 - api_s/wall_s]",
      lambda rs: fmt_pct(med([tool_share(r) for r in rs])))

table("median cost per run  [claude total_cost_usd]",
      lambda rs: fmt_usd(med([num(r,"cost_usd") for r in rs])))
PY
