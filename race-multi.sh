#!/usr/bin/env bash
# Screencast-friendly: all 3 agents run IN PARALLEL, each iterating through
# a list of cases sequentially. One stream file per agent accumulates output
# across all cases so a single tmux tail can follow a full multi-case run.
#
# usage:  ./race-multi.sh                 # defaults to tc1 tc2 tc3 tc4
#         ./race-multi.sh tc1 tc3 tc5

set -euo pipefail
cd "$(dirname "$0")"
BENCH_DIR="$PWD"

cases=("$@")
[ ${#cases[@]} -eq 0 ] && cases=(tc1 tc2 tc3 tc4)

for c in "${cases[@]}"; do
  [ -d "cases/$c" ] || { echo "no such case: $c" >&2; exit 1; }
done

[ -z "${ANTHROPIC_FOUNDRY_RESOURCE:-}" ] && { echo "ANTHROPIC_FOUNDRY_RESOURCE not set" >&2; exit 1; }
[ -z "${ANTHROPIC_FOUNDRY_API_KEY:-}" ] && { echo "ANTHROPIC_FOUNDRY_API_KEY not set" >&2; exit 1; }

AGENTS=(claude-max claude-foundry copilot)
stamp=$(date +%Y%m%d-%H%M%S)
RACEDIR="${RACEDIR:-$BENCH_DIR/results/race-multi/${stamp}}"
mkdir -p "$RACEDIR"

now() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time()'; }

echo "cases:  ${cases[*]}"
echo "out:    $RACEDIR"
echo ""

run_agent() {
  local agent="$1"
  local outdir="$RACEDIR/$agent"
  mkdir -p "$outdir"
  local stream
  stream="$outdir/stream.jsonl"
  : > "$stream"
  : > "$outdir/summary.csv"

  local case_id workdir prompt t0 t1 wall status
  for case_id in "${cases[@]}"; do
    workdir=$(mktemp -d -t "racem-${case_id}-${agent}-XXXXXX")
    bash "$BENCH_DIR/cases/${case_id}/setup.sh" "$workdir" >>"$outdir/setup.log" 2>&1

    printf '{"type":"_bench_case","case":"%s"}\n' "$case_id" >> "$stream"

    prompt=$(cat "$BENCH_DIR/cases/${case_id}/prompt.txt")
    t0=$(now)
    ( cd "$workdir" && bash "$BENCH_DIR/agents/${agent}.sh" "$prompt" "$outdir" ) \
      >>"$outdir/stdout.log" 2>>"$outdir/stderr.log" || true
    t1=$(now)
    wall=$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.2f", b-a}')

    if ( cd "$workdir" && bash "$BENCH_DIR/cases/${case_id}/verify.sh" ) >>"$outdir/verify.log" 2>&1; then
      status=PASS
    else
      status=FAIL
    fi
    echo "$case_id,$wall,$status" >> "$outdir/summary.csv"

    if [ "$agent" = "copilot" ]; then
      printf '\n=== END %s %s %ss ===\n' "$case_id" "$status" "$wall" >> "$stream"
    else
      printf '{"type":"_bench_case_end","case":"%s","status":"%s","wall_s":"%s"}\n' "$case_id" "$status" "$wall" >> "$stream"
    fi

    rm -rf "$workdir"
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
echo "waiting for all 3 agents to complete ${#cases[@]} case(s)..."
for pid in "${pids[@]}"; do wait "$pid" || true; done

echo ""
echo "=== summary ==="
printf "%-18s %-5s %8s  %s\n" "agent" "case" "wall_s" "verify"
for agent in "${AGENTS[@]}"; do
  while IFS=, read -r case_id wall status; do
    color=31
    [ "$status" = "PASS" ] && color=32
    printf "%-18s %-5s %8ss  \033[${color}m%s\033[0m\n" "$agent" "$case_id" "$wall" "$status"
  done < "$RACEDIR/$agent/summary.csv"
done
