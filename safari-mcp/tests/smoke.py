#!/usr/bin/env python3 -I
"""End-to-end test of the Safari MCP server.

Launches the binary and calls each tool on test data only:
a PRIVATE window (no history) opened by the server, with the local pages
tests/mcp-test-*.html and about:blank. Bookmark, history, Reading List
and tab group reads are filtered on the "mcp-test" marker (empty result accepted).
Nothing is added to the Reading List (add_to_reading_list is validated by probe 10).
Only closes the test window. Logs the duration and size of each call.
Usage: python3 -I tests/smoke.py [path to binary]
"""
import json
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BIN = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "bin/SafariMCP")
P1 = "file://" + os.path.join(ROOT, "tests", "mcp-test-1.html")
P2 = "file://" + os.path.join(ROOT, "tests", "mcp-test-2.html")

proc = subprocess.Popen([BIN], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
next_id = 0
fails = []
journal = []  # (tool, ms, bytes)


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
    line = proc.stdout.readline()
    if not line:
        raise RuntimeError("the server stopped")
    return json.loads(line)


def call(name, args=None, expect_error=False):
    t0 = time.time()
    res = rpc("tools/call", {"name": name, "arguments": args or {}})["result"]
    text = res["content"][0]["text"]
    ms = int((time.time() - t0) * 1000)
    journal.append((name, ms, len(text.encode())))
    print(f"   {name} ({ms} ms, {len(text.encode())} B)")
    if res.get("isError"):
        if not expect_error:
            check(False, f"{name} failed: {text}")
        return text
    if expect_error:
        check(False, f"{name} should have failed: {text[:200]}")
    return json.loads(text)


def check(cond, label):
    print(("  ✓ " if cond else "  ✗ ") + label)
    if not cond:
        fails.append(label)


def visibles():
    """IDs of visible Safari windows (IDs only, no content)."""
    out = subprocess.run(["osascript", "-e", 'tell application "Safari" to get id of every window whose visible is true'],
                         capture_output=True, text=True).stdout.strip()
    return {int(x) for x in out.split(",") if x.strip()}


debut = time.time()
avant = visibles()
W = None
try:
    print("== Protocol")
    init = rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "smoke", "version": "1"}})
    check(init["result"]["serverInfo"]["name"] == "safari", "initialize")
    check(len(init["result"]["instructions"].splitlines()) <= 10, "instructions ≤ 10 lines")
    rpc("notifications/initialized", notify=True)
    check(rpc("ping")["result"] == {}, "ping")
    tools = {t["name"]: t["annotations"] for t in rpc("tools/list")["result"]["tools"]}
    check(len(tools) == 14, f"tools/list: {len(tools)} tools")
    ro = {n for n, a in tools.items() if a["readOnlyHint"]}
    check(ro == {"list_tabs", "read_page", "list_reading_list", "list_bookmarks", "list_history", "list_tab_groups"}, f"readOnly: {sorted(ro)}")
    check([n for n, a in tools.items() if a["destructiveHint"]] == ["close", "delete_from_reading_list", "delete_history", "delete_tab_groups"], "destructive: close and the three deletions")
    check([n for n, a in tools.items() if a["openWorldHint"]] == ["run_js"], "openWorld: run_js only")
    check("add_to_reading_list" in tools, "add_to_reading_list present (tested in a probe, not in smoke)")
    check(rpc("methode/inconnue").get("error", {}).get("code") == -32601, "unknown method → -32601")
    check("unknown tool" in call("no_such_tool", expect_error=True), "unknown tool → isError")

    print("== Reads filtered on the test marker (before)")
    h_avant = len(call("list_history", {"text": "mcp-test", "limit": 100})["pages"])

    print("== Open (private window)")
    r = call("open", {"urls": [P1, P2], "private": True, "wait": True})
    W = r["window_id"]
    check(W not in avant, f"private window {W} is new")
    check([o.get("title") for o in r["tabs"]] == ["[mcp-test] page 1", "[mcp-test] page 2"], f"2 tabs loaded: {r['tabs']}")
    check([o["index"] for o in r["tabs"]] == [1, 2], "index 1 and 2")

    print("== Tabs")
    o = call("list_tabs", {"window_id": W})
    check(o["windows"] == 1 and len(o["tabs"]) == 2, f"2 tabs in the test window: {o}")
    check(o["tabs"][0].get("active") is True and o["tabs"][0]["url"] == P1, "tab 1 active, URL")
    check([x["index"] for x in call("list_tabs", {"window_id": W, "text": "PAGE 2"})["tabs"]] == [2], "text filter (case)")
    check(len(call("list_tabs", {"window_id": W, "limit": 1})["tabs"]) == 1, "limit")

    print("== Open in an existing window")
    r = call("open", {"urls": ["about:blank"], "window_id": W})
    check(r["tabs"][0]["index"] == 3, f"about:blank in tab 3: {r}")
    r = call("open", {"urls": [P2], "window_id": W, "wait": True})
    check(r["tabs"][0]["index"] == 4 and r["tabs"][0].get("title") == "[mcp-test] page 2", f"page 2 in tab 4: {r}")

    print("== Navigate")
    n = call("navigate", {"actions": [{"window_id": W, "index": 1, "url": P2}], "wait": True})["results"][0]
    check(n["ok"] and n.get("title") == "[mcp-test] page 2", f"go to a URL: {n}")
    n = call("navigate", {"actions": [{"window_id": W, "index": 1, "action": "back"}], "wait": True})["results"][0]
    check(n.get("title") == "[mcp-test] page 1", f"back: {n}")
    n = call("navigate", {"actions": [{"window_id": W, "index": 1, "action": "forward"}], "wait": True})["results"][0]
    check(n.get("title") == "[mcp-test] page 2", f"forward: {n}")
    n = call("navigate", {"actions": [{"window_id": W, "index": 1, "url": P1}, {"window_id": W, "index": 2, "action": "reload"}], "wait": True})["results"]
    check(all(x["ok"] for x in n) and [x.get("title") for x in n] == ["[mcp-test] page 1", "[mcp-test] page 2"], f"batch url + reload: {n}")
    n = call("navigate", {"actions": [{"window_id": W, "index": 2, "action": "activate"}]})["results"][0]
    check(n["ok"] and call("list_tabs", {"window_id": W})["tabs"][1].get("actif") is True, "activate tab 2")
    n = call("navigate", {"actions": [{"window_id": W, "index": 1, "action": "voler"}]}, expect_error=True)
    check("unknown action" in n, "unknown action refused")

    print("== Read page")
    p = call("read_page", {"tabs": [{"window_id": W, "index": 1}, {"window_id": W, "index": 2}]})["pages"]
    check("marqueur-mcp-test-1" in p[0].get("text", "") and "marqueur-mcp-test-2" in p[1].get("text", ""), "text of 2 tabs in one call")
    l = call("read_page", {"tabs": [{"window_id": W, "index": 1}], "format": "links"})["pages"][0]
    check(l.get("links") == [{"text": "link to 2", "url": P2}], f"links: {l.get('links')}")
    h = call("read_page", {"tabs": [{"window_id": W, "index": 1}], "format": "html"})["pages"][0]
    check("<h1>[mcp-test] page 1</h1>" in h.get("html", ""), "current html")
    t = call("read_page", {"tabs": [{"window_id": W, "index": 1}], "format": "html", "max_chars": 100})["pages"][0]
    check(t.get("truncated") is True and len(t["html"]) == 100, "truncation")
    e = call("read_page", {"tabs": [{"window_id": W, "index": 99}]})["pages"][0]
    check("error" in e, f"missing tab → per-item error: {e.get('error', '')[:80]}")

    print("== JavaScript")
    j = call("run_js", {"script": "document.title", "tabs": [{"window_id": W, "index": 1}, {"window_id": W, "index": 2}]})["results"]
    check([x.get("result") for x in j] == ["[mcp-test] page 1", "[mcp-test] page 2"], f"expression on 2 tabs: {j}")
    j = call("run_js", {"script": "return {n: document.links.length, h: location.protocol}", "tabs": [{"window_id": W, "index": 1}]})["results"][0]
    check(j.get("result") == {"n": 1, "h": "file:"}, f"object → JSON: {j}")
    j = call("run_js", {"script": "document.body.innerHTML = '<p>[mcp-test] injected</p>'; return document.body.innerText", "tabs": [{"window_id": W, "index": 3}]})["results"][0]
    check(j.get("result") == "[mcp-test] injected", f"function body on about:blank: {j}")
    j = call("run_js", {"script": "throw new Error('boum')", "tabs": [{"window_id": W, "index": 1}]})["results"][0]
    check(j["ok"] is False and "boum" in j.get("error", ""), f"JS exception: {j}")
    j = call("run_js", {"script": "return (", "tabs": [{"window_id": W, "index": 1}]})["results"][0]
    check(j["ok"] is False and "syntax" in j.get("error", ""), "syntax error reported")

    print("== Close tabs")
    f = call("close", {"tabs": [{"window_id": W, "index": 3, "expected_url": "https://pas-celle-ci"}]})
    check(f["closed"] == 0 and "different" in f["tabs"][0].get("error", ""), "expected_url protects the tab")
    f = call("close", {"tabs": [{"window_id": W, "index": 3}, {"window_id": W, "index": 4, "expected_url": P2}]})
    check(f["closed"] == 2, f"2 tabs closed in a batch (descending order): {f}")
    check(len(call("list_tabs", {"window_id": W})["tabs"]) == 2, "2 tabs left")

    print("== File reads (filtered on the test marker)")
    check(call("list_bookmarks", {"text": "[mcp-test]"})["bookmarks"] == [], "bookmarks: no test item")
    check(call("list_bookmarks", {"text": "[mcp-test]", "folders": True})["folders"] == [], "bookmark folders: no test folder")
    rl = call("list_reading_list", {"text": "mcp-test", "include_preview": True})["items"]
    check(all("mcp-test" in x["url"] or "mcp-test" in x["title"] for x in rl), f"Reading List: {len(rl)} test item(s) only")
    check(call("list_tab_groups", {"text": "[mcp-test]"})["groups"] == [], "tab groups: no test group")
    hs = call("list_history", {"text": "mcp-test", "limit": 100})["pages"]
    check(all("mcp-test" in x["url"] + x["title"] for x in hs), "filtered history: test pages only")
    check(len(hs) == h_avant, f"private window: no history entry added ({h_avant} → {len(hs)})")
    check(call("list_history", {"text": "mcp-test", "since": "2000-01-01", "until": "2000-01-02"})["pages"] == [], "date filter")
    check(call("list_history", {"domain": "mcp-test.invalid"})["pages"] == [], "domain filter")
    check("invalid date" in call("list_history", {"since": "yesterday"}, expect_error=True), "invalid date refused")

    print("== Close the test window")
    f = call("close", {"windows": [W]})
    check(f["windows"][0]["ok"] is True, "test window closed")
    W_ferme = W
    time.sleep(0.5)
    check(W_ferme not in visibles(), "test window gone")
finally:
    print("== Cleanup")
    if W is not None and W in visibles():
        subprocess.run(["osascript", "-e", f'tell application "Safari" to close window id {W}'])
        print(f"  window {W} closed during cleanup")
    check(visibles() == avant, "visible windows identical to before the test")
    proc.stdin.close()
    proc.wait(timeout=10)

total = time.time() - debut
lents = [(n, ms) for i, (n, ms, _) in enumerate(journal) if ms > 500]
print()
print(f"Total duration: {total:.1f} s, {len(journal)} tool calls")
print("Calls > 0.5 s: " + (", ".join(f"{n} {ms} ms" for n, ms in lents) or "none"))
print("✓ ALL PASS" if not fails else f"✗ {len(fails)} failure(s):\n  - " + "\n  - ".join(fails))
sys.exit(1 if fails else 0)
