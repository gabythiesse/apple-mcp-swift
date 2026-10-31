#!/usr/bin/env python3 -I
"""Benchmark of the Safari MCP server (same stdio protocol as smoke.py).

Opens a PRIVATE window through the server (about:blank, a heavy page, local test pages),
measures each call N times (median, p95, response size), runs probe 28 (cost of
AppleScript compilation versus raw Apple Events) on that window, then closes it.
Never touches the other windows (list_tabs is restricted to the test window).
Usage: python3 -I tests/bench.py [path to binary] [--n 20] [--json out.json] [--no-probe]
"""
import json
import math
import os
import statistics
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
args = sys.argv[1:]
N = int(args[args.index("--n") + 1]) if "--n" in args else 20
OUT = args[args.index("--json") + 1] if "--json" in args else None
PROBE = "--no-probe" not in args
pos = [a for i, a in enumerate(args) if not a.startswith("--") and (i == 0 or args[i - 1] not in ("--n", "--json"))]
BIN = pos[0] if pos else os.path.join(ROOT, "bin/SafariMCP")
HEAVY = "https://fr.wikipedia.org/wiki/France"
P1 = "file://" + os.path.join(ROOT, "tests", "mcp-test-1.html")
P2 = "file://" + os.path.join(ROOT, "tests", "mcp-test-2.html")

proc = subprocess.Popen([BIN], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
next_id = 0


def rpc(method, params=None, notify=False):
    global next_id
    msg = {"jsonrpc": "2.0", "method": method}
    if params is not None:
        msg["params"] = params
    if not notify:
        next_id += 1
        msg["id"] = next_id
    proc.stdin.write(json.dumps(msg) + "\n")
    proc.stdin.flush()
    if notify:
        return None
    return json.loads(proc.stdout.readline())


def call(name, a=None):
    """(parsed result, ms, bytes); raises on a tool error."""
    t0 = time.perf_counter()
    res = rpc("tools/call", {"name": name, "arguments": a or {}})["result"]
    ms = (time.perf_counter() - t0) * 1000
    text = res["content"][0]["text"]
    if res.get("isError"):
        raise RuntimeError(f"{name}: {text}")
    return json.loads(text), ms, len(text.encode())


def pct(xs, p):
    s = sorted(xs)
    return s[max(0, math.ceil(p * len(s)) - 1)]


results = {}


def bench(label, name, a, n=N):
    """a: arguments, or a function k -> arguments (varies from one run to the next)."""
    ms, size, last = [], 0, None
    for k in range(n):
        last, t, size = call(name, a(k) if callable(a) else a)
        ms.append(t)
    results[label] = {"median": round(statistics.median(ms), 1), "p95": round(pct(ms, 0.95), 1), "bytes": size}
    print(f"  {label:<44} median {statistics.median(ms):7.1f} ms   p95 {pct(ms, 0.95):7.1f} ms   {size:6d} B")
    return last


def visibles():
    out = subprocess.run(["osascript", "-e", 'tell application "Safari" to get id of every window whose visible is true'],
                         capture_output=True, text=True).stdout.strip()
    return {int(x) for x in out.split(",") if x.strip()}


avant = visibles()
W = None
try:
    rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "bench", "version": "1"}})
    rpc("notifications/initialized", notify=True)
    r, ms, _ = call("open", {"urls": ["about:blank", HEAVY, P1], "private": True, "wait": True})
    W = r["window_id"]
    print(f"Private window {W} opened in {ms:.0f} ms: {[t.get('title') for t in r['tabs']]}")
    t1, t2, t3 = ({"window_id": W, "index": i} for i in (1, 2, 3))

    print(f"== Baseline ({N} runs each)")
    last = bench("run_js document.title, about:blank", "run_js", {"script": "document.title", "tabs": [t1]})
    bare = len(json.dumps(last.get("results", [{}])[0].get("result", last.get("result", ""))).encode()) if isinstance(last, dict) else 0
    results["run_js envelope"] = {"bytes_bare_result": bare}
    bench("run_js document.title, heavy page", "run_js", {"script": "document.title", "tabs": [t2]})
    bench("read_page text, heavy page", "read_page", {"tabs": [t2], "format": "text"})
    # 30 tabs in the test window: 27 more local pages
    call("open", {"urls": [P2] * 27, "window_id": W})
    bench("list_tabs, 30 tabs (test window)", "list_tabs", {"window_id": W})
    bench("navigate + wait, local page", "navigate",
          lambda k: {"actions": [{"window_id": W, "index": 3, "url": P2 if k % 2 == 0 else P1}], "wait": True})

    if PROBE:
        print("== Probe 28 (AppleScript vs raw Apple Events) on the test window")
        src = os.path.join(ROOT, "sondes", "28_apple_events_bruts.swift")
        exe = os.path.join(ROOT, "sondes", ".bin", "28")
        if not os.path.exists(exe) or os.path.getmtime(exe) < os.path.getmtime(src):
            os.makedirs(os.path.dirname(exe), exist_ok=True)
            subprocess.run(["swiftc", "-O", src, "-o", exe], check=True)
        out = subprocess.run([exe, str(W), str(N)], capture_output=True, text=True, timeout=600).stdout
        print(out, end="")
        results["probe28"] = out
finally:
    if W is not None:
        try:
            call("close", {"windows": [W]})
        except Exception as e:
            print(f"close failed: {e}")
        time.sleep(0.5)
        if W in visibles():
            subprocess.run(["osascript", "-e", f'tell application "Safari" to close window id {W}'])
    print("Windows identical to before:", visibles() == avant)
    proc.stdin.close()
    proc.wait(timeout=10)

if OUT:
    with open(OUT, "w") as f:
        json.dump(results, f, indent=1, ensure_ascii=False)
