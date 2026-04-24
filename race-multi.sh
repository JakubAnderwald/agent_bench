#!/usr/bin/env bash
# Screencast-friendly: all 3 agents run IN PARALLEL, each iterating through
# a trial x case grid sequentially.
#
# Each agent writes directly to its own live master stream ($RACEDIR/<agent>/
# stream.jsonl) — this is what the tmux panes tail. _bench_trial, _bench_case,
# and _bench_case_end markers wrap each run so a post-race slicing step can
# carve per-run transcripts into $RACEDIR/raw/t<N>/<case>/<agent>/ — the same
# layout bench.sh produces, so metrics.sh can consume it unchanged.
#
# Set TRIALS=N (default 1) to loop the whole grid N times.
#
# usage:  ./race-multi.sh                 # defaults to tc1 tc2 tc3 tc4
#         ./race-multi.sh tc1 tc3 tc5
#         TRIALS=3 ./race-multi.sh

set -euo pipefail
cd "$(dirname "$0")"
BENCH_DIR="$PWD"

# Force C numeric locale so awk/perl emit `.` decimals.
export LC_ALL=C

cases=("$@")
[ ${#cases[@]} -eq 0 ] && cases=(tc1 tc2 tc3 tc4)

for c in "${cases[@]}"; do
  [ -d "cases/$c" ] || { echo "no such case: $c" >&2; exit 1; }
done

[ -z "${ANTHROPIC_FOUNDRY_RESOURCE:-}" ] && { echo "ANTHROPIC_FOUNDRY_RESOURCE not set" >&2; exit 1; }
[ -z "${ANTHROPIC_FOUNDRY_API_KEY:-}" ] && { echo "ANTHROPIC_FOUNDRY_API_KEY not set" >&2; exit 1; }

AGENTS=(claude-max claude-foundry copilot)
TRIALS=${TRIALS:-1}
stamp=$(date +%Y%m%d-%H%M%S)
RACEDIR="${RACEDIR:-$BENCH_DIR/results/race-multi/${stamp}}"
mkdir -p "$RACEDIR"

now() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time()'; }

echo "cases:   ${cases[*]}"
echo "trials:  $TRIALS"
echo "out:     $RACEDIR"
echo ""

run_agent() {
  local agent="$1"
  local outdir="$RACEDIR/$agent"
  mkdir -p "$outdir"
  local master="$outdir/stream.jsonl"
  : > "$master"
  : > "$outdir/summary.csv"
  local partial="$outdir/runs.partial.csv"
  : > "$partial"

  local trial case_id workdir prompt t0 t1 wall success status

  for trial in $(seq 1 "$TRIALS"); do
    printf '{"type":"_bench_trial","trial":%d}\n' "$trial" >> "$master"

    for case_id in "${cases[@]}"; do
      workdir=$(mktemp -d -t "racem-${case_id}-${agent}-XXXXXX")
      bash "$BENCH_DIR/cases/${case_id}/setup.sh" "$workdir" \
        >>"$outdir/setup.log" 2>&1

      printf '{"type":"_bench_case","case":"%s","trial":%d}\n' "$case_id" "$trial" >> "$master"

      prompt=$(cat "$BENCH_DIR/cases/${case_id}/prompt.txt")
      t0=$(now)
      # Agent appends straight into the master stream — no mirror, no buffering.
      ( cd "$workdir" && bash "$BENCH_DIR/agents/${agent}.sh" "$prompt" "$outdir" ) \
        >>"$outdir/stdout.log" 2>>"$outdir/stderr.log" || true
      t1=$(now)
      wall=$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.2f", b-a}')

      if ( cd "$workdir" && bash "$BENCH_DIR/cases/${case_id}/verify.sh" ) \
          >>"$outdir/verify.log" 2>&1; then
        success=1
        status=PASS
      else
        success=0
        status=FAIL
      fi

      printf '{"type":"_bench_case_end","case":"%s","trial":%d,"status":"%s","wall_s":"%s"}\n' \
        "$case_id" "$trial" "$status" "$wall" >> "$master"
      echo "t${trial},$case_id,$wall,$status" >> "$outdir/summary.csv"

      # Each agent writes its own partial CSV — merged after all workers finish
      # so we don't need cross-process locking (no flock on macOS).
      echo "$trial,$case_id,$agent,$wall,$success" >> "$partial"

      rm -rf "$workdir"
    done
  done
}

pids=()
for agent in "${AGENTS[@]}"; do
  run_agent "$agent" &
  pid=$!
  pids+=("$pid")
  echo "launched $agent  pid=$pid"
done

echo ""
echo "waiting for all 3 agents to complete ${#cases[@]} case(s) x $TRIALS trial(s)..."
for pid in "${pids[@]}"; do wait "$pid" || true; done

# --- Post-process: carve master streams into per-run files + build runs.csv ---
python3 - "$RACEDIR" "${AGENTS[*]}" <<'PY'
import json, re, sys
from pathlib import Path

racedir = Path(sys.argv[1])
agents  = sys.argv[2].split()
raw_dir = racedir / "raw"

TURN_RE = re.compile(r'"type":"(?:assistant|assistant\.turn_end)"')
TOOL_RE = re.compile(r'"type":"(?:tool_use|tool\.execution_start)"')

def slice_master(agent):
    """Split $RACEDIR/<agent>/stream.jsonl into per-run stream.jsonl files
    using the _bench_trial / _bench_case / _bench_case_end markers."""
    master = racedir / agent / "stream.jsonl"
    if not master.exists(): return
    trial = None
    case  = None
    buf   = []
    def flush():
        if trial is not None and case is not None:
            dest = raw_dir / f"t{trial}" / case / agent
            dest.mkdir(parents=True, exist_ok=True)
            (dest / "stream.jsonl").write_text("".join(buf))
        buf.clear()
    for line in master.open():
        if '"_bench_trial"' in line:
            flush()
            try: trial = json.loads(line).get("trial")
            except json.JSONDecodeError: pass
        elif '"_bench_case"' in line and '"_bench_case_end"' not in line:
            flush()
            try:
                d = json.loads(line)
                case  = d.get("case")
                trial = d.get("trial", trial)
            except json.JSONDecodeError: pass
        elif '"_bench_case_end"' in line:
            buf.append(line)
            flush()
            case = None
        else:
            buf.append(line)
    flush()

for a in agents:
    slice_master(a)

# Assemble runs.csv from per-agent partials, enriched with turn/tool counts
# parsed from the carved per-run streams.
rows = []
for a in agents:
    partial = racedir / a / "runs.partial.csv"
    if not partial.exists(): continue
    for line in partial.open():
        trial, case_id, agent, wall, success = line.strip().split(",")
        stream = raw_dir / f"t{trial}" / case_id / agent / "stream.jsonl"
        turns = tools = 0
        if stream.exists():
            text = stream.read_text()
            turns = len(TURN_RE.findall(text))
            tools = sum(1 for l in text.splitlines()
                          if TOOL_RE.search(l) and '"toolName":"report_intent"' not in l)
        rows.append((int(trial), case_id, agent, wall, int(success), turns, tools))

rows.sort(key=lambda r: (r[0], r[1], r[2]))
with (racedir / "runs.csv").open("w") as f:
    f.write("trial,case,agent,wall_s,success,turns,tool_calls\n")
    for r in rows:
        f.write(",".join(str(x) for x in r) + "\n")

print(f"wrote {racedir/'runs.csv'}  ({len(rows)} rows)")
print(f"per-run transcripts under {raw_dir}/")
PY

echo ""
echo "=== summary ==="
printf "%-18s %-4s %-5s %8s  %s\n" "agent" "trial" "case" "wall_s" "verify"
for agent in "${AGENTS[@]}"; do
  while IFS=, read -r trial_tag case_id wall status; do
    color=31
    [ "$status" = "PASS" ] && color=32
    printf "%-18s %-4s %-5s %8ss  \033[${color}m%s\033[0m\n" \
      "$agent" "$trial_tag" "$case_id" "$wall" "$status"
  done < "$RACEDIR/$agent/summary.csv"
done
