#!/usr/bin/env bash
# Screencast-friendly: all 3 agents run IN PARALLEL, each iterating through
# a trial x case grid sequentially. Two output layouts coexist:
#
#   $RACEDIR/<agent>/stream.jsonl       # master live stream, one per agent,
#                                         accumulates across trials+cases for
#                                         the tmux tail panes
#   $RACEDIR/raw/t<N>/<case>/<agent>/   # per-run transcripts, same shape as
#     stream.jsonl                       # bench.sh writes, so metrics.sh can
#     stdout.log                         # join the master runs.csv against
#     stderr.log                         # per-run `result` events
#     verify.log
#   $RACEDIR/runs.csv                   # bench.sh-schema rows, one per run
#
# Set TRIALS=N (default 1) to loop the whole grid N times.
#
# usage:  ./race-multi.sh                 # defaults to tc1 tc2 tc3 tc4
#         ./race-multi.sh tc1 tc3 tc5
#         TRIALS=3 ./race-multi.sh

set -euo pipefail
cd "$(dirname "$0")"
BENCH_DIR="$PWD"

# Force C numeric locale so awk/perl emit `.` decimals — locales like de_DE
# write `54,47` and break CSV parsing downstream.
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

CSV="$RACEDIR/runs.csv"
echo "trial,case,agent,wall_s,success,turns,tool_calls" > "$CSV"

now() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time()'; }

echo "cases:   ${cases[*]}"
echo "trials:  $TRIALS"
echo "out:     $RACEDIR"
echo ""

run_agent() {
  local agent="$1"
  local master="$RACEDIR/$agent/stream.jsonl"
  mkdir -p "$RACEDIR/$agent"
  : > "$master"
  : > "$RACEDIR/$agent/summary.csv"

  local trial case_id workdir prompt t0 t1 wall success turns tools status
  local per_run_dir per_run_stream mirror_pid

  for trial in $(seq 1 "$TRIALS"); do
    printf '{"type":"_bench_trial","trial":%d}\n' "$trial" >> "$master"

    for case_id in "${cases[@]}"; do
      per_run_dir="$RACEDIR/raw/t${trial}/${case_id}/${agent}"
      per_run_stream="$per_run_dir/stream.jsonl"
      mkdir -p "$per_run_dir"
      : > "$per_run_stream"

      workdir=$(mktemp -d -t "racem-${case_id}-${agent}-XXXXXX")
      bash "$BENCH_DIR/cases/${case_id}/setup.sh" "$workdir" \
        >>"$per_run_dir/setup.log" 2>&1

      printf '{"type":"_bench_case","case":"%s","trial":%d}\n' "$case_id" "$trial" >> "$master"

      # Mirror this run's per-file stream into the master in real time for
      # the tmux pane. `tail -F -s 0.1` polls every 100ms; lag is invisible
      # on a screencast.
      tail -F -s 0.1 -n 0 "$per_run_stream" >> "$master" 2>/dev/null &
      mirror_pid=$!

      prompt=$(cat "$BENCH_DIR/cases/${case_id}/prompt.txt")
      t0=$(now)
      ( cd "$workdir" && bash "$BENCH_DIR/agents/${agent}.sh" "$prompt" "$per_run_dir" ) \
        >>"$per_run_dir/stdout.log" 2>>"$per_run_dir/stderr.log" || true
      t1=$(now)
      wall=$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.2f", b-a}')

      # Let tail drain the last events, then stop it.
      sleep 0.3
      kill "$mirror_pid" 2>/dev/null || true
      wait "$mirror_pid" 2>/dev/null || true

      if ( cd "$workdir" && bash "$BENCH_DIR/cases/${case_id}/verify.sh" ) \
          >>"$per_run_dir/verify.log" 2>&1; then
        success=1
        status=PASS
      else
        success=0
        status=FAIL
      fi

      # Same counting rules as bench.sh — filter out Copilot's report_intent
      # meta-tool so counts are comparable across agent vocabularies.
      turns=$(grep -cE '"type":"(assistant|assistant\.turn_end)"' "$per_run_stream" 2>/dev/null || true)
      tools=$(grep -E '"type":"(tool_use|tool\.execution_start)"' "$per_run_stream" 2>/dev/null \
              | grep -vc '"toolName":"report_intent"' || true)
      [ -z "$turns" ] && turns=0
      [ -z "$tools" ] && tools=0

      printf '{"type":"_bench_case_end","case":"%s","trial":%d,"status":"%s","wall_s":"%s"}\n' \
        "$case_id" "$trial" "$status" "$wall" >> "$master"
      echo "t${trial},$case_id,$wall,$status" >> "$RACEDIR/$agent/summary.csv"

      # Serialise runs.csv writes across the 3 parallel agent workers.
      (
        flock 9
        echo "$trial,$case_id,$agent,$wall,$success,$turns,$tools" >> "$CSV"
      ) 9>"$CSV.lock"

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

rm -f "$CSV.lock"

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

echo ""
echo "wrote $CSV"
echo "per-run transcripts under $RACEDIR/raw/"
