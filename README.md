# agent-bench

Speed benchmark comparing three coding agents on six practical tasks:

- `claude-max` — Claude Code on a Max subscription
- `claude-foundry` — Claude Code using the native Azure AI Foundry provider
- `copilot` — GitHub Copilot CLI (the agentic one)

Each test case runs in an isolated scratch workdir seeded from a tarball or a pinned git clone, so reruns are reproducible.

## Test cases

| ID | Shape | Repo | Measures |
|----|-------|------|----------|
| tc1 | pure exploration, read-only | `ky` | exploration throughput, no edits |
| tc2 | single localised edit | fresh Next.js app | one-shot edit latency |
| tc3 | multi-file refactor (3 files) | Next.js + seeded components | parallel-edit efficiency |
| tc4 | bugfix from failing tests | seeded mini-lib | test → read → edit → rerun loop |
| tc5 | feature + test | seeded FastAPI mini-app | end-to-end feature work |
| tc6 | deep read in large repo | `express` | exploration focus in noisy codebase |

## Prerequisites

```bash
# CLIs
claude --version          # Claude Code
copilot --version         # GitHub Copilot CLI (agentic; NOT `gh copilot suggest`)
gh auth status            # copilot reads auth from gh
tmux -V                   # for screencast.sh (brew install tmux)
pnpm -v node -v           # for the Next.js template build
python3 --version         # 3.10+
uv --version              # optional; speeds up TC5 venv build

# Max plan auth — one-time login
claude /login

# Foundry auth — export before running
export CLAUDE_CODE_USE_FOUNDRY=1
export ANTHROPIC_FOUNDRY_RESOURCE="your-foundry-resource-name"
export ANTHROPIC_FOUNDRY_API_KEY="..."          # rotate if shared
# optional override (default is claude-opus-4-6, matching the other agents):
# export ANTHROPIC_MODEL="claude-opus-4-1"
```

If `copilot`'s flags differ on your install, edit `agents/copilot.sh` — the script has a header comment listing the common variants.

## Agent configuration

All three agents are pinned to the same model and reasoning effort so differences in the table reflect provider/infra, not model choice:

| Agent | Model | Permissions | Effort |
|-------|-------|-------------|--------|
| `claude-max` | `claude-opus-4-6` | `--dangerously-skip-permissions` | `--effort high` |
| `claude-foundry` | `claude-opus-4-6` (via `ANTHROPIC_MODEL`) | `--dangerously-skip-permissions` | `--effort high` |
| `copilot` | `claude-opus-4.6` (override with `COPILOT_MODEL`) | `--yolo` | `--effort high` |

Copilot's model slug uses a dot (`claude-opus-4.6`); the Claude CLI uses a hyphen (`claude-opus-4-6`). If your Azure Foundry deployment doesn't have Opus 4.6 enabled, override per run: `ANTHROPIC_MODEL=claude-opus-4-1 ./bench.sh`.

## Run the benchmark

```bash
cd ~/code/agent-bench
chmod +x prepare.sh bench.sh race.sh screencast.sh summarize.sh agents/*.sh cases/*/*.sh

./prepare.sh              # one-time; clones repos, builds templates (~2 min)
./screencast.sh tc2       # parallel race in tmux, for recording
./bench.sh                # full benchmark: 3 trials × 6 cases × 3 agents = 54 runs
./summarize.sh            # median wall time + pass rate per (case, agent)
```

Override trial count (e.g. one pass for a quick check):

```bash
TRIALS=1 ./bench.sh
```

Outputs:

- `results/runs.csv` — one row per run
- `results/raw/t<N>/<case>/<agent>/` — raw transcripts, verify logs

## Screencast mode

Two variants, both opening a single tmux window with three labelled agent panes + a driver pane at the bottom. You start your recording, press ENTER in the driver pane, and all three agents launch in parallel.

### Single case: `./screencast.sh <case>`

```bash
./screencast.sh tc2     # quick localised edit, ~10–30 s per agent
./screencast.sh tc3     # multi-file refactor — biggest visible gap
./screencast.sh tc4     # bugfix-loop
```

### Multi-case: `./screencast-multi.sh [cases...]`

Each agent iterates through the given case list sequentially, all three in parallel. Useful for a single take that covers the whole suite.

```bash
./screencast-multi.sh              # defaults to tc1 tc2 tc3 tc4
./screencast-multi.sh tc2 tc3 tc4  # custom list
```

Outputs go to `results/race-multi/<timestamp>/`.

Layout:

```
+--- CLAUDE-MAX ------+--- CLAUDE-FOUNDRY --+--- COPILOT ----------+
| [  0.0s] START      | [  0.0s] START      | (raw tail here)      |
| [  1.2s] TEXT  ...  | [  1.8s] TOOL  Read | ...                  |
| [  2.4s] TOOL  Edit | [  3.1s] TOOL  Edit |                      |
| [  5.6s] DONE       | ...                 |                      |
+---------------------+---------------------+----------------------+
|                            DRIVER                                |
|  press ENTER to start; finish-order table prints here            |
+------------------------------------------------------------------+
```

The two Claude panes show parsed activity (one line per tool call / text turn, with elapsed seconds). The Copilot pane shows raw stdout — its log format isn't Anthropic-stream-json, so we don't pretty-print it.

**Recording:** start QuickTime Player → Cmd-Shift-5 → select the tmux window → click Record → then press ENTER in the driver pane. For crisper text output that replays in a terminal, use `asciinema rec demo.cast` in place of QuickTime.

### Why parallel is fine here

These agents spend 95% of their time waiting on LLM HTTP responses. CPU contention between three tailing JSONL streams is negligible, so running them simultaneously barely skews wall times. Parallel execution gives viewers the thing they came for: the visual "X finished while Y was still thinking."

If you want the *representative* feel of working with each tool (sequential, clean cache states), run `TRIALS=1 ./bench.sh` off-camera instead and use those numbers.

## Screencast script (2–3 minutes)

A good recording plan:

1. **Intro (10 s)** — run `./screencast.sh tc2`, three panes visible and empty, driver pane shows the prompt. Read the prompt out loud.
2. **tc2 (~15–30 s per agent)** — press ENTER, watch the race. All three should succeed; gap comes from raw latency.
3. **Kill session, restart with tc3 (~30–90 s per agent)** — multi-file refactor. Expect the biggest visible gap; whichever agent batches parallel edits pulls ahead.
4. **tc4 (~30–120 s per agent)** — bugfix with test loop. Shows agent-loop efficiency; Copilot's pane may stay quieter if its format doesn't stream.
5. **Summary (20 s)** — cut to `./summarize.sh` output from a prior full `./bench.sh` run.

Skip tc5/tc6 on camera — tc5's pip check is boring, tc6's output is a wall of text.

## Notes and caveats

- **Prompt caching** makes trial 2+ faster on Claude Code. `bench.sh` rotates agent order per trial to distribute that warmup across providers; the median of 3 trials is what you report.
- **Rate limits on Max plan** can spike wall times 10×. Run off-peak (EU morning = US night) if you see outliers.
- **Foundry region matters** — a US endpoint from an EU machine adds ~100 ms per tool-call round trip, which compounds across 20+ turns.
- **Copilot CLI** doesn't produce Anthropic-style `stream-json`, so its `turns` / `tool_calls` columns will read 0. Wall time and success/fail are still accurate, which is what the headline compares.
- **Permissions are fully bypassed** — `--dangerously-skip-permissions` on Claude, `--yolo` on Copilot. Without these, the agent pauses for approvals on any shell command (e.g. `pytest` in tc5) and you're timing your own reaction.
- **tc2 verify** accepts the full-height Tailwind class (`min-h-screen`, `h-dvh`, etc.) in either `app/page.tsx` or `app/layout.tsx` — both are valid centering patterns. Centering classes themselves (`items-center`, `justify-center`, `place-items-center`) must still be in `app/page.tsx` alongside the heading.

## Troubleshooting

- `prepare.sh` fails on `pnpm create next-app` — update pnpm (`npm i -g pnpm`), try again.
- `bench.sh` says `copilot CLI not on PATH` — install the agentic copilot CLI (not `gh copilot`); confirm with `copilot --help`.
- Claude Foundry calls 401 — confirm `CLAUDE_CODE_USE_FOUNDRY=1` is exported and `ANTHROPIC_FOUNDRY_RESOURCE` matches your Azure AI Foundry resource name.
- TC5 fails `pytest` import — ensure the template was built with deps installed; delete `templates/tc5-fastapi.tar.gz` and rerun `./prepare.sh`.
