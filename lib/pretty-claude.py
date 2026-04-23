#!/usr/bin/env python3
# Read Claude Code stream-json from stdin, emit one human-readable line per event.
# Used in the screencast tmux panes so viewers can follow the agent live.
import sys
import json
import time

START = time.time()


def elapsed():
    return f"{time.time() - START:5.1f}s"


def summarize_tool(name, inp):
    if name in ("Read", "Edit", "Write", "NotebookEdit"):
        path = inp.get("file_path") or inp.get("path") or ""
        return path.split("/")[-1][:48]
    if name == "Bash":
        return (inp.get("command") or "").replace("\n", " ")[:52]
    if name in ("Grep", "Glob"):
        return (inp.get("pattern") or "")[:48]
    if name == "Agent":
        return (inp.get("description") or "")[:48]
    keys = list(inp.keys())
    return ",".join(keys[:3])[:48]


def main():
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
        if typ == "system" and d.get("subtype") == "init":
            print(f"[{t}] START", flush=True)
        elif typ == "assistant":
            for c in d.get("message", {}).get("content", []):
                ct = c.get("type")
                if ct == "text":
                    lines = (c.get("text") or "").strip().splitlines()
                    if lines:
                        print(f"[{t}] TEXT  {lines[0][:80]}", flush=True)
                elif ct == "tool_use":
                    name = c.get("name", "?")
                    summary = summarize_tool(name, c.get("input") or {})
                    print(f"[{t}] TOOL  {name:<6} {summary}", flush=True)
        elif typ == "result":
            sub = d.get("subtype", "")
            dur = (d.get("duration_ms") or 0) / 1000
            if sub == "success":
                print(f"[{t}] DONE  ({dur:.1f}s)", flush=True)
            else:
                print(f"[{t}] FAIL  {sub}", flush=True)
        elif typ == "_bench_case":
            case = d.get("case", "?")
            print(f"[{t}] ---- CASE {case} ----", flush=True)
        elif typ == "_bench_case_end":
            case = d.get("case", "?")
            status = d.get("status", "?")
            wall = d.get("wall_s", "?")
            print(f"[{t}] ---- {case} {status} {wall}s ----", flush=True)


if __name__ == "__main__":
    main()
