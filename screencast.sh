#!/usr/bin/env bash
# One-command screencast launcher. Opens a tmux window with:
#
#   +-- CLAUDE-MAX ---+-- CLAUDE-FOUNDRY -+-- COPILOT -------+
#   | live activity   | live activity     | live activity    |
#   | ...             | ...               | ...              |
#   +-----------------+-------------------+------------------+
#   |                   DRIVER (you type here)               |
#   +--------------------------------------------------------+
#
# Sequence once attached:
#   1. All 3 tail panes are waiting on empty stream files.
#   2. Driver pane says "press ENTER to start race".
#   3. You start your screen recording.
#   4. You press ENTER in the driver pane.
#   5. All 3 agents launch simultaneously; activity streams into the 3 top panes.
#   6. Driver pane prints the finish-order table when everyone is done.
#   7. Press ENTER again to close the tmux session.
#
# usage: ./screencast.sh tc2     (default tc2)
#        ./screencast.sh tc3
#        ./screencast.sh tc4

set -euo pipefail
cd "$(dirname "$0")"

case_id="${1:-tc2}"
[ -d "cases/$case_id" ] || { echo "no such case: $case_id" >&2; exit 1; }
command -v tmux >/dev/null || { echo "install tmux: brew install tmux" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 required" >&2; exit 1; }
: "${ANTHROPIC_FOUNDRY_RESOURCE:?ANTHROPIC_FOUNDRY_RESOURCE not set}"
: "${ANTHROPIC_FOUNDRY_API_KEY:?ANTHROPIC_FOUNDRY_API_KEY not set}"

stamp=$(date +%Y%m%d-%H%M%S)
RACEDIR="$PWD/results/race/${case_id}-${stamp}"
mkdir -p "$RACEDIR/claude-max" "$RACEDIR/claude-foundry" "$RACEDIR/copilot"
: > "$RACEDIR/claude-max/stream.jsonl"
: > "$RACEDIR/claude-foundry/stream.jsonl"
: > "$RACEDIR/copilot/stream.log"

SESSION="bench-${case_id}-${stamp}"
PRETTY="$PWD/lib/pretty-claude.py"

tmux kill-session -t "$SESSION" 2>/dev/null || true

# --- pane 0: CLAUDE-MAX tail ---
tmux new-session -d -s "$SESSION" -x 240 -y 64 -c "$PWD" \
  "tail -F '$RACEDIR/claude-max/stream.jsonl' | python3 -u '$PRETTY'"

# --- pane 1: CLAUDE-FOUNDRY tail ---
tmux split-window -h -t "$SESSION" -c "$PWD" \
  "tail -F '$RACEDIR/claude-foundry/stream.jsonl' | python3 -u '$PRETTY'"

# --- pane 2: COPILOT tail (raw, no stream-json) ---
tmux split-window -h -t "$SESSION" -c "$PWD" \
  "tail -F '$RACEDIR/copilot/stream.log'"

tmux select-layout -t "$SESSION" even-horizontal

# --- pane 3: DRIVER, full width at the bottom ---
# `-f` makes the split span the whole window instead of splitting just the active pane.
tmux split-window -v -f -l "30%" -t "$SESSION" -c "$PWD" \
  "printf '\nCASE: %s\nPROMPT:\n' '$case_id'; cat 'cases/$case_id/prompt.txt'; \
   printf '\n\n>>> press ENTER to start the race (start recording first!) '; \
   read; \
   echo; echo '=== GO ==='; \
   RACEDIR='$RACEDIR' ./race.sh $case_id; \
   echo; echo '>>> press ENTER to close'; read; \
   tmux kill-session -t $SESSION"

# --- pane borders and labels ---
tmux set -t "$SESSION" pane-border-status top
tmux set -t "$SESSION" pane-border-format " #{pane_title} "
tmux select-pane -t "$SESSION":0.0 -T "CLAUDE-MAX"
tmux select-pane -t "$SESSION":0.1 -T "CLAUDE-FOUNDRY"
tmux select-pane -t "$SESSION":0.2 -T "COPILOT"
tmux select-pane -t "$SESSION":0.3 -T "DRIVER"

# highlight which pane has focus (helpful on camera)
tmux set -t "$SESSION" pane-active-border-style "fg=yellow,bold"
tmux set -t "$SESSION" pane-border-style "fg=colour240"

# focus driver so user can just press ENTER
tmux select-pane -t "$SESSION":0.3

tmux attach -t "$SESSION"
