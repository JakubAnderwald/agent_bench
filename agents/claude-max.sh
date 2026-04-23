#!/usr/bin/env bash
# Claude Code using Max plan (subscription auth from ~/.claude/).
# Inputs: $1 prompt, $2 outdir (absolute path for stream output).
set -euo pipefail
PROMPT="$1"; OUTDIR="$2"

# Force subscription path by unsetting API/provider envs.
unset ANTHROPIC_API_KEY
unset ANTHROPIC_AUTH_TOKEN
unset ANTHROPIC_BASE_URL
unset ANTHROPIC_MODEL
unset ANTHROPIC_FOUNDRY_RESOURCE
unset ANTHROPIC_FOUNDRY_API_KEY
unset CLAUDE_CODE_USE_BEDROCK
unset CLAUDE_CODE_USE_VERTEX
unset CLAUDE_CODE_USE_FOUNDRY

# --dangerously-skip-permissions  bypass all permission checks (yolo)
# --model claude-opus-4-6         pin model for cross-agent parity
# --max-turns 30                  hard cap so a runaway agent doesn't sit forever
# --output-format stream-json     machine-parseable, gives us turn/tool counts
# --verbose                       required with stream-json
claude -p "$PROMPT" \
  --dangerously-skip-permissions \
  --model claude-opus-4-6 \
  --effort high \
  --max-turns 30 \
  --output-format stream-json \
  --verbose \
  >> "$OUTDIR/stream.jsonl"
