#!/usr/bin/env python3
# Read GitHub Copilot CLI --output-format json from stdin, emit one
# human-readable line per event. Mirror of lib/pretty-claude.py for the
# copilot pane in screencast-multi.sh.
import sys
import json
import time

START = time.time()

# Copilot's meta-narration tool — filter out to match bench.sh's tool-count
# exclusion and keep the pane comparable to the Claude panes.
IGNORED_TOOLS = {"report_intent"}


def elapsed():
    return f"{time.time() - START:5.1f}s"


def summarize_tool(name, args):
    if name in ("view", "create", "str_replace_editor"):
        path = args.get("path") or args.get("file_path") or ""
        return path.split("/")[-1][:48]
    if name == "bash":
        return (args.get("command") or "").replace("\n", " ")[:52]
    if name == "grep":
        return (args.get("pattern") or "")[:48]
    if name == "find":
        return (args.get("pattern") or args.get("path") or "")[:48]
    keys = list(args.keys())
    return ",".join(keys[:3])[:48]


def main():
    started = False
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            d = json.loads(line)
        except Exception:
            continue
        typ = d.get("type")
        t = elapsed()
        data = d.get("data") or {}

        if typ == "_bench_case":
            case = d.get("case", "?")
            print(f"[{t}] ---- CASE {case} ----", flush=True)
        elif typ == "_bench_case_end":
            case = d.get("case", "?")
            status = d.get("status", "?")
            wall = d.get("wall_s", "?")
            print(f"[{t}] ---- {case} {status} {wall}s ----", flush=True)
        elif typ == "user.message" and not started:
            started = True
            print(f"[{t}] START", flush=True)
        elif typ == "assistant.reasoning":
            content = (data.get("content") or "").strip().splitlines()
            if content:
                print(f"[{t}] THINK {content[0][:80]}", flush=True)
        elif typ == "tool.execution_start":
            name = data.get("toolName") or "?"
            if name in IGNORED_TOOLS:
                continue
            summary = summarize_tool(name, data.get("arguments") or {})
            print(f"[{t}] TOOL  {name:<6} {summary}", flush=True)
        elif typ == "result":
            usage = d.get("usage") or {}
            dur = (usage.get("sessionDurationMs") or 0) / 1000
            if d.get("exitCode") == 0:
                print(f"[{t}] DONE  ({dur:.1f}s)", flush=True)
            else:
                print(f"[{t}] FAIL  exit={d.get('exitCode')}", flush=True)
        elif typ == "abort":
            reason = data.get("reason") or "?"
            print(f"[{t}] FAIL  abort ({reason})", flush=True)


if __name__ == "__main__":
    main()
