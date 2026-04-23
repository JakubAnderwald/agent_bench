#!/usr/bin/env bash
# GitHub Copilot CLI (the agentic one, not `gh copilot suggest`).
# VERIFY FLAGS on your installed version: run `copilot --help` and adjust.
# Known variants seen in the wild:
#   copilot -p "$PROMPT" --allow-all-tools
#   copilot --prompt "$PROMPT" --yes
#   copilot agent run --prompt "$PROMPT"
# If your version differs, edit the `copilot` invocation below.
set -euo pipefail
PROMPT="$1"; OUTDIR="$2"

# Copilot CLI reads GH auth from `gh auth status` — run `gh auth login` if needed.
# It doesn't produce Anthropic-style stream-json; we capture stdout verbatim and
# set turns/tool counts to 0 in bench.sh (still get wall time + success).

copilot -p "$PROMPT" \
  --yolo \
  --model "${COPILOT_MODEL:-claude-opus-4.6}" \
  --effort high \
  --log-dir "$OUTDIR/copilot-logs" \
  >> "$OUTDIR/stream.log"
