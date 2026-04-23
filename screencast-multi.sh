#!/usr/bin/env bash
# Multi-case screencast: one tmux window with 3 agent panes + 1 driver pane.
# All 3 agents run in parallel, each iterating through tc1..tc4 sequentially.
#
#   +-- CLAUDE-MAX ---+-- CLAUDE-FOUNDRY -+-- COPILOT -------+
#   | tc1..tc4 live   | tc1..tc4 live     | tc1..tc4 live    |
#   +-----------------+-------------------+------------------+
#   |                   DRIVER (you type here)               |
#   +--------------------------------------------------------+
#
# usage: ./screencast-multi.sh               # tc1 tc2 tc3 tc4
#        ./screencast-multi.sh tc1 tc2 tc3   # custom case list

set -euo pipefail
cd "$(dirname "$0")"

cases=("$@")
[ ${#cases[@]} -eq 0 ] && cases=(tc1 tc2 tc3 tc4)
for c in "${cases[@]}"; do
  [ -d "cases/$c" ] || { echo "no such case: $c" >&2; exit 1; }
done

command -v tmux >/dev/null || { echo "install tmux: brew install tmux" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 required" >&2; exit 1; }
: "${ANTHROPIC_FOUNDRY_RESOURCE:?ANTHROPIC_FOUNDRY_RESOURCE not set}"
: "${ANTHROPIC_FOUNDRY_API_KEY:?ANTHROPIC_FOUNDRY_API_KEY not set}"

stamp=$(date +%Y%m%d-%H%M%S)
RACEDIR="$PWD/results/race-multi/${stamp}"
mkdir -p "$RACEDIR/claude-max" "$RACEDIR/claude-foundry" "$RACEDIR/copilot"
: > "$RACEDIR/claude-max/stream.jsonl"
: > "$RACEDIR/claude-foundry/stream.jsonl"
: > "$RACEDIR/copilot/stream.log"

SESSION="bench-multi-${stamp}"
PRETTY="$PWD/lib/pretty-claude.py"
CASES_STR="${cases[*]}"

tmux kill-session -t "$SESSION" 2>/dev/null || true

# --- pane 0: CLAUDE-MAX tail ---
tmux new-session -d -s "$SESSION" -x 240 -y 64 -c "$PWD" \
  "tail -F '$RACEDIR/claude-max/stream.jsonl' | python3 -u '$PRETTY'"

# --- pane 1: CLAUDE-FOUNDRY tail ---
tmux split-window -h -t "$SESSION" -c "$PWD" \
  "tail -F '$RACEDIR/claude-foundry/stream.jsonl' | python3 -u '$PRETTY'"

# --- pane 2: COPILOT tail ---
tmux split-window -h -t "$SESSION" -c "$PWD" \
  "tail -F '$RACEDIR/copilot/stream.log'"

tmux select-layout -t "$SESSION" even-horizontal

# --- pane 3: DRIVER ---
tmux split-window -v -f -l "30%" -t "$SESSION" -c "$PWD" \
  "printf '\nCASES: %s\n' '$CASES_STR'; \
   printf '\n>>> press ENTER to start the race (start recording first!) '; \
   read; \
   echo; echo '=== GO ==='; \
   RACEDIR='$RACEDIR' ./race-multi.sh $CASES_STR; \
   echo; echo '>>> press ENTER to close'; read; \
   tmux kill-session -t $SESSION"

tmux set -t "$SESSION" pane-border-status top
tmux set -t "$SESSION" pane-border-format " #{pane_title} "
tmux select-pane -t "$SESSION":0.0 -T "CLAUDE-MAX"
tmux select-pane -t "$SESSION":0.1 -T "CLAUDE-FOUNDRY"
tmux select-pane -t "$SESSION":0.2 -T "COPILOT"
tmux select-pane -t "$SESSION":0.3 -T "DRIVER"

tmux set -t "$SESSION" pane-active-border-style "fg=yellow,bold"
tmux set -t "$SESSION" pane-border-style "fg=colour240"

tmux select-pane -t "$SESSION":0.3
tmux attach -t "$SESSION"
