#!/usr/bin/env bash
# Full benchmark: sequential, 3 trials per (case x agent).
# Rotates agent order per trial to distribute warmup bias.
# Writes results/runs.csv.

set -euo pipefail
cd "$(dirname "$0")"
BENCH_DIR="$PWD"

# Force C numeric locale so awk/perl print `.` as decimal separator.
# Without this, locales like de_DE write `54,47` and break CSV parsing.
export LC_ALL=C

AGENTS=(claude-max claude-foundry copilot)
CASES=(tc1 tc2 tc3 tc4 tc5 tc6)
TRIALS=${TRIALS:-3}

# --- preflight ---
command -v claude >/dev/null || { echo "claude CLI not on PATH" >&2; exit 1; }
command -v copilot >/dev/null || { echo "copilot CLI not on PATH" >&2; exit 1; }
[ -z "${ANTHROPIC_FOUNDRY_RESOURCE:-}" ] && { echo "ANTHROPIC_FOUNDRY_RESOURCE not set" >&2; exit 1; }
[ -z "${ANTHROPIC_FOUNDRY_API_KEY:-}" ] && { echo "ANTHROPIC_FOUNDRY_API_KEY not set" >&2; exit 1; }
[ -f templates/nextjs.tar.gz ] || { echo "run ./prepare.sh first" >&2; exit 1; }

mkdir -p results/raw
CSV=results/runs.csv
[ -f "$CSV" ] || echo "trial,case,agent,wall_s,success,turns,tool_calls" > "$CSV"

# portable subsecond timer
now() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time()'; }

# deterministic per-trial rotation (no random = reproducible)
rotate() {
  local t=$1
  local n=${#AGENTS[@]}
  local i
  for ((i=0; i<n; i++)); do
    echo "${AGENTS[$(( (i + t) % n ))]}"
  done
}

run_one() {
  local trial=$1 case_id=$2 agent=$3
  local workdir outdir prompt t0 t1 wall success turns tools
  workdir=$(mktemp -d -t "bench-${case_id}-${agent}-XXXXXX")
  outdir="results/raw/t${trial}/${case_id}/${agent}"
  mkdir -p "$outdir"

  printf "\033[90m[%s] t%d %-4s %-15s\033[0m " "$(date +%H:%M:%S)" "$trial" "$case_id" "$agent"

  bash "cases/${case_id}/setup.sh" "$workdir" >"$outdir/setup.log" 2>&1
  prompt=$(cat "cases/${case_id}/prompt.txt")

  t0=$(now)
  ( cd "$workdir" && bash "$BENCH_DIR/agents/${agent}.sh" "$prompt" "$BENCH_DIR/$outdir" ) \
    >"$outdir/stdout.log" 2>"$outdir/stderr.log" || true
  t1=$(now)
  wall=$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.2f", b-a}')

  if ( cd "$workdir" && bash "$BENCH_DIR/cases/${case_id}/verify.sh" ) >"$outdir/verify.log" 2>&1; then
    success=1
  else
    success=0
  fi

  # Count turns and tool calls across both Claude (stream-json) and Copilot
  # (--output-format json) vocabularies. `report_intent` is Copilot's meta
  # narration tool — filter it out so tool counts stay comparable to Claude.
  turns=$(grep -cE '"type":"(assistant|assistant\.turn_end)"' "$outdir/stream.jsonl" 2>/dev/null || true)
  tools=$(grep -E '"type":"(tool_use|tool\.execution_start)"' "$outdir/stream.jsonl" 2>/dev/null \
          | grep -vc '"toolName":"report_intent"' || true)
  [ -z "$turns" ] && turns=0
  [ -z "$tools" ] && tools=0

  echo "$trial,$case_id,$agent,$wall,$success,$turns,$tools" >> "$CSV"
  if [ "$success" = "1" ]; then
    printf "\033[32m%6ss  ok\033[0m  (turns=%s tools=%s)\n" "$wall" "$turns" "$tools"
  else
    printf "\033[31m%6ss FAIL\033[0m (turns=%s tools=%s)\n" "$wall" "$turns" "$tools"
  fi

  rm -rf "$workdir"
}

for trial in $(seq 1 "$TRIALS"); do
  order=($(rotate "$trial"))
  echo ""
  echo "=== trial $trial  order: ${order[*]} ==="
  for case_id in "${CASES[@]}"; do
    for agent in "${order[@]}"; do
      run_one "$trial" "$case_id" "$agent"
    done
  done
done

echo ""
echo "done. summarize: ./summarize.sh"
