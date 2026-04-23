#!/usr/bin/env bash
# Screencast-friendly: run all 3 agents IN PARALLEL on one case.
# Each agent gets its own workdir so they don't conflict.
# Prints a live leaderboard at the end.
#
# usage:  ./race.sh tc2
#         ./race.sh tc3

set -euo pipefail
cd "$(dirname "$0")"

case_id=${1:-tc2}
[ -d "cases/$case_id" ] || { echo "no such case: $case_id" >&2; exit 1; }
[ -z "${ANTHROPIC_FOUNDRY_RESOURCE:-}" ] && { echo "ANTHROPIC_FOUNDRY_RESOURCE not set" >&2; exit 1; }
[ -z "${ANTHROPIC_FOUNDRY_API_KEY:-}" ] && { echo "ANTHROPIC_FOUNDRY_API_KEY not set" >&2; exit 1; }

AGENTS=(claude-max claude-foundry copilot)
stamp=$(date +%Y%m%d-%H%M%S)
# RACEDIR can be overridden by screencast.sh so tmux panes know where to tail.
RACEDIR="${RACEDIR:-$PWD/results/race/${case_id}-${stamp}}"
mkdir -p "$RACEDIR"

now() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time()'; }
prompt=$(cat "cases/${case_id}/prompt.txt")

echo "case:   $case_id"
echo "prompt: $prompt"
echo "out:    $RACEDIR"
echo ""

pids=()
starts=()

for agent in "${AGENTS[@]}"; do
  workdir=$(mktemp -d -t "race-${case_id}-${agent}-XXXXXX")
  outdir="$RACEDIR/$agent"
  mkdir -p "$outdir"
  bash "cases/${case_id}/setup.sh" "$workdir" >"$outdir/setup.log" 2>&1
  echo "$workdir" > "$outdir/.workdir"

  t0=$(now)
  echo "$t0" > "$outdir/.t0"
  (
    cd "$workdir"
    bash "$OLDPWD/agents/${agent}.sh" "$prompt" "$OLDPWD/$outdir" \
      >"$OLDPWD/$outdir/stdout.log" 2>"$OLDPWD/$outdir/stderr.log" || true
    t1=$(perl -MTime::HiRes=time -e 'printf "%.3f\n", time()')
    echo "$t1" > "$OLDPWD/$outdir/.t1"
  ) &
  pid=$!
  pids+=("$pid")
  echo "launched $agent  pid=$pid  workdir=$workdir"
done

echo ""
echo "waiting for all 3..."
for pid in "${pids[@]}"; do wait "$pid" || true; done

echo ""
echo "=== results ==="
printf "%-18s %8s   %s\n" "agent" "wall_s" "verify"
for agent in "${AGENTS[@]}"; do
  outdir="$RACEDIR/$agent"
  workdir=$(cat "$outdir/.workdir")
  t0=$(cat "$outdir/.t0")
  t1=$(cat "$outdir/.t1")
  wall=$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.2f", b-a}')
  if ( cd "$workdir" && bash "$OLDPWD/cases/${case_id}/verify.sh" ) >"$outdir/verify.log" 2>&1; then
    status="\033[32mPASS\033[0m"
  else
    status="\033[31mFAIL\033[0m"
  fi
  printf "%-18s %8s   %b\n" "$agent" "$wall" "$status"
  rm -rf "$workdir"
done
