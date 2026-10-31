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
PAGES = "file://" + os.path.join(ROOT, "tests", "pages")

# Pages locales servies en http : 127.0.0.1 et localhost sont deux origines, ce qui donne une iframe cross-origin sans réseau
import http.server
import socketserver
import threading


class Quiet(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **k):
        super().__init__(*a, directory=os.path.join(ROOT, "tests"), **k)

    def log_message(self, *a):
        pass


httpd = socketserver.ThreadingTCPServer(("127.0.0.1", 0), Quiet)
threading.Thread(target=httpd.serve_forever, daemon=True).start()
HTTP = f"http://127.0.0.1:{httpd.server_address[1]}/pages"

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
    ins = init["result"]["instructions"]
    check(all(w in ins for w in ("page_info", "snapshot", "act", "run_js")), "instructions guide to page_info, snapshot, act, run_js last")
    rpc("notifications/initialized", notify=True)
    check(rpc("ping")["result"] == {}, "ping")
    tools = {t["name"]: t["annotations"] for t in rpc("tools/list")["result"]["tools"]}
    check(len(tools) == 27, f"tools/list: {len(tools)} tools")
    ro = {n for n, a in tools.items() if a["readOnlyHint"]}
    check(ro == {"list_tabs", "read_page", "page_info", "snapshot", "find", "list_reading_list", "list_bookmarks", "list_history", "list_tab_groups"}, f"readOnly: {sorted(ro)}")
    check([n for n, a in tools.items() if a["destructiveHint"]] == ["close", "delete_from_reading_list", "delete_history", "delete_tab_groups"], "destructive: close and the three deletions")
    check(sorted(n for n, a in tools.items() if a["openWorldHint"]) == ["act", "run_js"], "openWorld: run_js and act")
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
    n = call("navigate", {"actions": [{"window_id": W, "index": 1, "url": P2}], "wait": True})
    check("error" not in n and n.get("title") == "[mcp-test] page 2", f"go to a URL: {n}")
    n = call("navigate", {"actions": [{"window_id": W, "index": 1, "action": "back"}], "wait": True})
    check(n.get("title") == "[mcp-test] page 1", f"back: {n}")
    n = call("navigate", {"actions": [{"window_id": W, "index": 1, "action": "forward"}], "wait": True})
    check(n.get("title") == "[mcp-test] page 2", f"forward: {n}")
    n = call("navigate", {"actions": [{"window_id": W, "index": 1, "url": P1}, {"window_id": W, "index": 2, "action": "reload"}], "wait": True})["results"]
    check(all("error" not in x for x in n) and [x.get("title") for x in n] == ["[mcp-test] page 1", "[mcp-test] page 2"], f"batch url + reload: {n}")
    n = call("navigate", {"actions": [{"window_id": W, "index": 2, "action": "activate"}]})
    check("error" not in n and call("list_tabs", {"window_id": W})["tabs"][1].get("active") is True, "activate tab 2")
    n = call("navigate", {"actions": [{"window_id": W, "index": 1, "action": "voler"}]}, expect_error=True)
    check("unknown action" in n, "unknown action refused")

    print("== Read page")
    p = call("read_page", {"tabs": [{"window_id": W, "index": 1}, {"window_id": W, "index": 2}], "format": "text"})["pages"]
    check("marqueur-mcp-test-1" in p[0].get("text", "") and "marqueur-mcp-test-2" in p[1].get("text", ""), "text of 2 tabs in one call")
    m = call("read_page", {"tabs": [{"window_id": W, "index": 1}]})
    check(m.get("markdown", "").startswith("# [mcp-test] page 1") and "marqueur-mcp-test-1" in m["markdown"], f"markdown by default: {m}")
    l = call("read_page", {"tabs": [{"window_id": W, "index": 1}], "format": "links"})
    check(l.get("links") == [{"text": "link to 2", "url": P2}], f"links: {l.get('links')}")
    h = call("read_page", {"tabs": [{"window_id": W, "index": 1}], "format": "html"})
    check("<h1>[mcp-test] page 1</h1>" in h.get("html", ""), "current html")
    t = call("read_page", {"tabs": [{"window_id": W, "index": 1}], "format": "html", "max_chars": 100})
    check(t.get("truncated") is True and len(t["html"]) == 100 and t.get("length", 0) > 100, "truncation with length")
    t2 = call("read_page", {"tabs": [{"window_id": W, "index": 1}], "format": "html", "max_chars": 100, "offset": 100})
    check(t2.get("offset") == 100 and t2["html"] and t2["html"] != t["html"], "offset reads the rest")
    e = call("read_page", {"tabs": [{"window_id": W, "index": 99}]}, expect_error=True)
    check("not found" in e, f"missing tab → error: {e[:80]}")
    e = call("read_page", {"tabs": [{"window_id": W, "index": 1}, {"window_id": W, "index": 99}]})["pages"]
    check("error" in e[1] and "markdown" in e[0], "batch: per-item error")

    print("== JavaScript")
    j = call("run_js", {"script": "document.title", "tabs": [{"window_id": W, "index": 1}, {"window_id": W, "index": 2}]})["results"]
    check([x.get("result") for x in j] == ["[mcp-test] page 1", "[mcp-test] page 2"], f"expression on 2 tabs: {j}")
    j = call("run_js", {"script": "return {n: document.links.length, h: location.protocol}", "tabs": [{"window_id": W, "index": 1}]})
    check(j.get("result") == {"n": 1, "h": "file:"}, f"object → JSON: {j}")
    j = call("run_js", {"script": "document.body.innerHTML = '<p>[mcp-test] injected</p>'; return document.body.innerText", "tabs": [{"window_id": W, "index": 3}]})
    check(j.get("result") == "[mcp-test] injected", f"function body on about:blank: {j}")
    j = call("run_js", {"script": "throw new Error('boum')", "tabs": [{"window_id": W, "index": 1}]}, expect_error=True)
    check("boum" in j and "line 1" in j, f"JS exception with line: {j}")
    j = call("run_js", {"script": "return (", "tabs": [{"window_id": W, "index": 1}]}, expect_error=True)
    check("syntax" in j, "syntax error reported")
    j = call("run_js", {"script": "await new Promise(r => setTimeout(() => r(42), 100))", "tabs": [{"window_id": W, "index": 1}]})
    check(j.get("result") == 42, f"await: {j}")
    j = call("run_js", {"script": "await new Promise(r => setTimeout(r, 5000))", "timeout": 300, "tabs": [{"window_id": W, "index": 1}]}, expect_error=True)
    check("timed out" in j, "async timeout")
    j = call("run_js", {"script": "alert('[mcp-test]'); return confirm('ok?')", "tabs": [{"window_id": W, "index": 1}]})
    check(j.get("result") is True and [d["type"] for d in j.get("dialogs", [])] == ["alert", "confirm"], f"dialogs intercepted: {j}")
    j = call("run_js", {"script": "document.querySelector('a')", "tabs": [{"window_id": W, "index": 1}]})
    check(str(j.get("result", "")).startswith("<a>"), f"DOM node described: {j}")
    j = call("run_js", {"script": "'x'.repeat(30000)", "max_chars": 1000, "tabs": [{"window_id": W, "index": 1}]})
    j2 = call("run_js", {"script": "'x'.repeat(30000)", "max_chars": 1000, "offset": 29500, "tabs": [{"window_id": W, "index": 1}]})
    check(j.get("length") == 30000 and len(j2["result"]) == 500, "run_js truncation + offset")

    print("== Perception (local pages)")
    r = call("open", {"urls": [HTTP + "/frames.html", PAGES + "/big.html"], "window_id": W, "wait": True})
    F, B = {"window_id": W, "index": r["tabs"][0]["index"]}, {"window_id": W, "index": r["tabs"][1]["index"]}
    time.sleep(0.3)
    i = call("page_info", F)
    check(i.get("iframes") == 2 and i.get("cross_origin_iframes") == 1 and i.get("shadow_roots") == 1, f"page_info frames: {i}")
    sn = call("snapshot", F)
    txt = sn.get("text", "")
    check('button "frame button"' in txt and 'button "shadow button"' in txt and "cross-origin" in txt, f"snapshot crosses same-origin iframe and shadow DOM, flags cross-origin: {txt}")
    fd = call("find", dict(F, text="SHADOW buttön"))["matches"]
    check(fd and fd[0]["name"] == "shadow button" and fd[0]["visible"] is True, f"find ignores case and accents: {fd[:1]}")
    fd = call("find", dict(F, near="frame field", role="button"))["matches"]
    check(fd and fd[0]["name"] == "frame button", f"find near: {fd[:1]}")
    t0 = time.time()
    sn = call("snapshot", dict(B, max_chars=2000))
    ms = (time.time() - t0) * 1000
    check(sn.get("elements", 0) >= 5000 and sn.get("length", 0) > 2000 and sn.get("next_offset"), f"snapshot 10000 elements: {sn.get('elements')} lines, paginated")
    check(ms < 500, f"snapshot 10000 elements in {ms:.0f} ms (< 500)")
    sn2 = call("snapshot", dict(B, max_chars=2000, offset=sn["next_offset"]))
    check(sn2.get("text", "").split("\n")[0].split(" ")[0].startswith("e") and sn2.get("offset") == sn["next_offset"], "snapshot offset continues")
    ref = txt.split('button "top button"')[0].split("\n")[-1].split(" ")[0]
    call("run_js", {"script": "document.getElementById('top').remove()", "tabs": [F]})
    e = call("snapshot", dict(F, ref=ref), expect_error=True)
    check("stale ref" in e, f"stale ref → clear error: {e}")

    print("== Actions (local pages)")
    r = call("open", {"urls": [HTTP + "/alert.html", HTTP + "/editor.html", HTTP + "/infinite.html", HTTP + "/../mcp-test-1.html"], "window_id": W, "wait": True})
    AL, ED, IN, NV = ({"window_id": W, "index": t["index"]} for t in r["tabs"])
    c = call("click", dict(AL, text="Show alert"))
    check([d["type"] for d in c.get("dialogs", [])] == ["alert"] and "after alert" in call("run_js", {"script": "document.getElementById('out').textContent", "tabs": [AL]})["result"], f"click: alert intercepted, no freeze: {c}")
    c = call("click", dict(AL, text="Ask confirm", accept_dialogs=False))
    check(c.get("dialogs", [{}])[0].get("answer") is False, "confirm answered Cancel on request")
    c = call("click", dict(F, text="frame button"))
    check("clicked inside" in json.dumps(c), f"click inside a same-origin iframe: {c}")
    c = call("check", dict(F, label="shadow check"))
    check(c.get("checked") is True, f"check in shadow DOM: {c}")
    c = call("type", dict(F, label="frame field", value="bonjour"))
    check(c.get("value") == "bonjour", f"type in iframe field: {c}")
    c = call("type", dict(ED, label="Message body", value="hello world"))
    p_ = call("press", dict(ED, keys=["Cmd+A", "Cmd+B"]))
    html = call("run_js", {"script": "document.getElementById('ed').innerHTML", "tabs": [ED]})["result"]
    check(c.get("value") == "hello world" and "<b>hello world</b>" in html, f"contenteditable: type then Cmd+B → {html} {p_}")
    c = call("hover", dict(IN, text="Hover menu"))
    check(any("Sub item A" in x for x in c.get("appeared", [])), f"hover opens the menu: {c}")
    c = call("scroll", dict(IN, to="bottom"))
    check(c.get("loaded_more") is True and c.get("new_elements", 0) >= 20, f"infinite scroll loads more: {c}")
    w_ = call("wait", dict(IN, text="Sub item B"))
    check(w_.get("met") is True and "Sub item B" in w_.get("found", ""), f"wait text: {w_}")
    e = call("wait", dict(IN, text="never there", timeout=200), expect_error=True)
    check("timed out" in e, "wait timeout")
    c = call("click", dict(NV, text="link to 2"))
    check(c.get("navigated") is True and c.get("title") == "[mcp-test] page 2", f"click follows a link: {c}")
    a_ = call("act", dict(NV, steps=[{"action": "goto", "url": HTTP + "/../mcp-test-1.html"}, {"action": "read", "selector": "#marq"},
                                     {"action": "click", "text": "link to 2"}, {"action": "read", "selector": "p"}]))
    check([x["action"] for x in a_.get("steps", [])] == ["goto", "read", "click", "read"] and a_["steps"][3].get("text") == "marqueur-mcp-test-2", f"act across a navigation: {a_}")
    a_ = call("act", dict(NV, steps=[{"action": "click", "text": "no such thing", "timeout": 200}]), expect_error=True)
    j_ = json.loads(a_)
    check(j_.get("failed_step") == 1 and "snapshot" in j_, f"act failure: step, error and snapshot: {a_[:200]}")

    print("== Close tabs")
    f = call("close", {"tabs": [{"window_id": W, "index": 3, "expected_url": "https://pas-celle-ci"}]})
    check(f["closed"] == 0 and "different" in f["tabs"][0].get("error", ""), "expected_url protects the tab")
    f = call("close", {"tabs": [{"window_id": W, "index": 3}, {"window_id": W, "index": 4, "expected_url": P2}]})
    check(f["closed"] == 2, f"2 tabs closed in a batch (descending order): {f}")
    check(len(call("list_tabs", {"window_id": W})["tabs"]) == 8, "8 tabs left")

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
    httpd.shutdown()

total = time.time() - debut
lents = [(n, ms) for i, (n, ms, _) in enumerate(journal) if ms > 500]
print()
print(f"Total duration: {total:.1f} s, {len(journal)} tool calls")
print("Calls > 0.5 s: " + (", ".join(f"{n} {ms} ms" for n, ms in lents) or "none"))
print("✓ ALL PASS" if not fails else f"✗ {len(fails)} failure(s):\n  - " + "\n  - ".join(fails))
sys.exit(1 if fails else 0)
