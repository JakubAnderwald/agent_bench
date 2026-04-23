#!/usr/bin/env bash
# Claude Code using the native Azure AI Foundry provider.
# Requires ANTHROPIC_FOUNDRY_RESOURCE and ANTHROPIC_FOUNDRY_API_KEY in the env.
# Optionally override ANTHROPIC_MODEL (defaults to claude-opus-4-6 to match Max).
set -euo pipefail
PROMPT="$1"; OUTDIR="$2"

: "${ANTHROPIC_FOUNDRY_RESOURCE:?ANTHROPIC_FOUNDRY_RESOURCE not set}"
: "${ANTHROPIC_FOUNDRY_API_KEY:?ANTHROPIC_FOUNDRY_API_KEY not set}"

export CLAUDE_CODE_USE_FOUNDRY=1
export ANTHROPIC_FOUNDRY_RESOURCE
export ANTHROPIC_FOUNDRY_API_KEY
export ANTHROPIC_MODEL="${ANTHROPIC_MODEL:-claude-opus-4-6}"
unset ANTHROPIC_API_KEY
unset ANTHROPIC_AUTH_TOKEN
unset ANTHROPIC_BASE_URL
unset CLAUDE_CODE_USE_BEDROCK
unset CLAUDE_CODE_USE_VERTEX

claude -p "$PROMPT" \
  --dangerously-skip-permissions \
  --model "$ANTHROPIC_MODEL" \
  --effort high \
  --max-turns 30 \
  --output-format stream-json \
  --verbose \
  >> "$OUTDIR/stream.jsonl"
