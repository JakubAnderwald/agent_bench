#!/usr/bin/env bash
# GitHub Copilot CLI (the agentic one, not `gh copilot suggest`).
# VERIFY FLAGS on your installed version: run `copilot --help` and adjust.
set -euo pipefail
PROMPT="$1"; OUTDIR="$2"

# Copilot CLI reads GH auth from `gh auth status` — run `gh auth login` if needed.
# --output-format json emits JSONL (one event per line) that bench.sh parses
# for turn and tool-call counts, comparable (within a factor of 1) to Claude's
# stream-json.

copilot -p "$PROMPT" \
  --yolo \
  --model "${COPILOT_MODEL:-claude-opus-4.6}" \
  --effort high \
  --output-format json \
  --log-dir "$OUTDIR/copilot-logs" \
  >> "$OUTDIR/stream.jsonl"
