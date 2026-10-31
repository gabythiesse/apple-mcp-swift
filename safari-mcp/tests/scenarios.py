#!/usr/bin/env python3 -I
"""Real-page scenarios for the Safari MCP server (not run by smoke.py: needs the network).

Everything happens in a PRIVATE window opened by the server and closed at the end; local pages
(tests/pages) are served on 127.0.0.1 by this script. For each scenario: number of tool calls,
total time and response size, measured on the scenario calls only (opening the page is setup).
Usage: python3 -I tests/scenarios.py [path to binary] [--json out.json] [--only name]
"""
import http.server
import json
import os
import socketserver
import subprocess
import sys
import threading
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
args = sys.argv[1:]
OUT = args[args.index("--json") + 1] if "--json" in args else None
ONLY = args[args.index("--only") + 1] if "--only" in args else None
pos = [a for i, a in enumerate(args) if not a.startswith("--") and (i == 0 or args[i - 1] not in ("--json", "--only"))]
BIN = pos[0] if pos else os.path.join(ROOT, "bin/SafariMCP")


class Quiet(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **k):
        super().__init__(*a, directory=os.path.join(ROOT, "tests"), **k)

    def log_message(self, *a):
        pass


httpd = socketserver.ThreadingTCPServer(("127.0.0.1", 0), Quiet)
threading.Thread(target=httpd.serve_forever, daemon=True).start()
LOCAL = f"http://127.0.0.1:{httpd.server_address[1]}/pages"

proc = subprocess.Popen([BIN], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
next_id = 0


def rpc(method, params=None):
    global next_id
    next_id += 1
    proc.stdin.write(json.dumps({"jsonrpc": "2.0", "id": next_id, "method": method, "params": params or {}}) + "\n")
    proc.stdin.flush()
    return json.loads(proc.stdout.readline())


def raw_call(name, a):
    t0 = time.perf_counter()
    r = rpc("tools/call", {"name": name, "arguments": a})["result"]
    ms = (time.perf_counter() - t0) * 1000
    text = r["content"][0]["text"]
    try:
        val = json.loads(text)
    except ValueError:
        val = text
    return val, ms, len(text.encode()), bool(r.get("isError"))


def visibles():
    out = subprocess.run(["osascript", "-e", 'tell application "Safari" to get id of every window whose visible is true'],
                         capture_output=True, text=True).stdout.strip()
    return {int(x) for x in out.split(",") if x.strip()}


# (name, page, scenario, max calls, max ms, url, steps(tab) -> [(tool, args)], check(results) -> (ok, note))
def sc_wiki(t):
    return [("read_page", dict(t))]


def ck_wiki(r):
    md = r[0].get("markdown", "") if isinstance(r[0], dict) else ""
    return ("| --- |" in md and md.startswith("# France"), f"{len(md.encode())} B of markdown, table {'yes' if '| --- |' in md else 'no'}, length {r[0].get('length')}")


def sc_react(t):
    return [("act", dict(t, steps=[
        {"action": "type", "label": "Full name", "value": "Gaby"},
        {"action": "type", "label": "Email", "value": "gaby@example.com"},
        {"action": "select", "label": "Country", "option": "France"},
        {"action": "check", "text": "I accept the terms"},
        {"action": "click", "text": "Send", "role": "button", "expect": "Thanks"},
        {"action": "read", "selector": "[role=status]"}]))]


def ck_react(r):
    s = r[0].get("steps", []) if isinstance(r[0], dict) else []
    txt = s[-1].get("text", "") if s else ""
    return (txt.startswith("Thanks Gaby"), txt or str(r[0])[:200])


def sc_drawio(t):
    return [("act", dict(t, steps=[
        {"action": "wait", "selector": ".geMenubar", "timeout": 15000},
        {"action": "wait", "text_gone": "Démarrage", "timeout": 15000},
        {"action": "click", "text": "Suppléments", "role": "button"},
        {"action": "click", "text": "Modifier le diagramme"},
        {"action": "read", "selector": "textarea"},
        {"action": "click", "text": "Annuler", "role": "button"}]))]


def ck_drawio(r):
    s = r[0].get("steps", []) if isinstance(r[0], dict) else []
    xml = next((x.get("text", "") for x in s if x["action"] == "read"), "")
    levels = sorted({x.get("level", "dom") for x in s if x["action"] == "click"})
    return ("<mxGraphModel" in xml and len(s) == 6, f"XML {len(xml)} chars, click levels {levels}" if xml else str(r[0])[:300])


def sc_youtube(t):
    return [("snapshot", dict(t, max_chars=3000)), ("scroll", dict(t, to="bottom"))]


def ck_youtube(r):
    sn = r[0].get("text", "") if isinstance(r[0], dict) else ""
    sh = r[0].get("shadow_roots", 0) if isinstance(r[0], dict) else 0
    sc = r[1] if isinstance(r[1], dict) else {}
    return (" button " in sn and sc.get("loaded_more") is True,
            f"{sn.count(chr(10)) + 1} lines, {sh} open shadow roots, +{sc.get('new_elements')} elements after scroll")


def sc_editor(t):
    return [("act", dict(t, steps=[
        {"action": "type", "label": "Message body", "value": "Bonjour Gaby"},
        {"action": "press", "keys": ["Cmd+A", "Cmd+B"]},
        {"action": "js", "script": "document.getElementById('ed').innerHTML"}]))]


def ck_editor(r):
    s = r[0].get("steps", []) if isinstance(r[0], dict) else []
    html = s[-1].get("result", "") if s else ""
    return ("<b>Bonjour Gaby</b>" in html, html or str(r[0])[:200])


def sc_pdf(t):
    return [("read_page", dict(t))]


def ck_pdf(r):
    o = r[0] if isinstance(r[0], dict) else {}
    return (o.get("page_type") == "pdf" and "Dummy PDF" in o.get("text", ""), f"page_type {o.get('page_type')}, text {o.get('text', '')[:40]!r}")


def sc_frames(t):
    return [("snapshot", dict(t))]


def ck_frames(r):
    s = r[0].get("text", "") if isinstance(r[0], dict) else ""
    return ('"frame button"' in s and "cross-origin" in s and '"shadow button"' in s, "same-origin crossed, cross-origin flagged, shadow DOM read")


def sc_alert(t):
    return [("click", dict(t, text="Show alert"))]


def ck_alert(r):
    d = r[0].get("dialogs", []) if isinstance(r[0], dict) else []
    return (d and d[0]["type"] == "alert", f"dialogs {d}")


def sc_big(t):
    return [("snapshot", dict(t))]


def ck_big(r):
    o = r[0] if isinstance(r[0], dict) else {}
    return (o.get("elements", 0) >= 5000, f"{o.get('elements')} lines over 10009 elements, first page {len(o.get('text', ''))} chars")


def sc_gdocs(t):
    return [("page_info", dict(t)), ("type", dict(t, value="Bonjour", mode="native"))]


def ck_gdocs(r):
    i = r[0] if isinstance(r[0], dict) else {}
    canvas = "canvas" in i.get("page_type", "")
    sent = isinstance(r[1], dict) and "error" not in r[1]
    # le texte d'un document Google Docs est dessiné dans un canvas : seul un document modifiable (compte connecté) le prouverait
    written = sent and "Bonjour" in json.dumps(r[1], ensure_ascii=False)
    note = f"page_type {i.get('page_type')!r}; native keystrokes {'sent' if sent else 'not sent'}: {str(r[1])[:120]}"
    if sent and not written:
        note += " — not proven: a logged-out private window only gets a view-only document"
    return (canvas and written, note)


SCENARIOS = [
    ("wikipedia", "Wikipedia FR, long article", "read_page markdown with a table", 1, 1000, "https://fr.wikipedia.org/wiki/France", sc_wiki, ck_wiki),
    ("react", "React form (local page, React from unpkg)", "act: 3 fields, check, submit, read the message", 1, 2000, LOCAL + "/form-react.html", sc_react, ck_react),
    ("drawio", "app.diagrams.net", "act: Extras menu, Edit diagram, read XML, close", 1, 5000, "https://app.diagrams.net/", sc_drawio, ck_drawio),
    ("youtube", "YouTube (search results: the logged-out home has no feed)", "snapshot, scroll to bottom loads videos", 2, 4000,
     "https://www.youtube.com/results?search_query=safari+browser", sc_youtube, ck_youtube),
    ("editor", "contenteditable editor (local page: Gmail/Notion need an account)", "type then Cmd+B", 1, 2000, LOCAL + "/editor.html", sc_editor, ck_editor),
    ("pdf", "PDF in Safari", "read_page gives page_type pdf and the text", 1, 1000, "https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf", sc_pdf, ck_pdf),
    ("frames", "same-origin and cross-origin iframes (local page)", "snapshot crosses one, flags the other", 1, 500, LOCAL + "/frames.html", sc_frames, ck_frames),
    ("alert", "alert() on click (local page)", "click does not freeze, dialog logged", 1, 500, LOCAL + "/alert.html", sc_alert, ck_alert),
    ("big", "10,000 elements (local page)", "interactive snapshot", 1, 300, LOCAL + "/big.html", sc_big, ck_big),
    ("gdocs", "Google Docs (public view-only doc)", "page_info says canvas app, native type writes", 2, 3000,
     "https://docs.google.com/document/d/195j9eDD3ccgjQRttHhJPymLJUCOUjs-jmwTrekvdjFE/edit", sc_gdocs, ck_gdocs),
]

avant = visibles()
W = None
rows = []
try:
    rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "scenarios", "version": "1"}})
    r, _, _, _ = raw_call("open", {"urls": ["about:blank"], "private": True})
    W = r["window_id"]
    for key, page, what, max_calls, max_ms, url, steps, check in SCENARIOS:
        if ONLY and key != ONLY:
            continue
        o, _, _, err = raw_call("open", {"urls": [url], "window_id": W, "wait": True})
        t = {"window_id": W, "index": o["tabs"][0]["index"]} if not err else None
        if t is None:
            rows.append(dict(key=key, page=page, ok=False, note=f"setup failed: {o}"))
            continue
        time.sleep(0.5)
        results, total_ms, total_b = [], 0.0, 0
        for tool, a in steps(t):
            v, ms, b, e = raw_call(tool, a)
            results.append(v if not e else {"error": v})
            total_ms += ms
            total_b += b
        ok, note = check(results)
        calls = len(results)
        row = dict(key=key, page=page, scenario=what, calls=calls, max_calls=max_calls, ms=round(total_ms), max_ms=max_ms,
                   kb=round(total_b / 1024, 1), ok=bool(ok), within=bool(ok) and calls <= max_calls and total_ms <= max_ms, note=note)
        rows.append(row)
        flag = "✓" if row["within"] else ("~" if ok else "✗")
        print(f"{flag} {key:<10} {calls}/{max_calls} calls  {total_ms:6.0f}/{max_ms} ms  {row['kb']:5.1f} KB  {note}")
        raw_call("close", {"tabs": [t]})
finally:
    if W is not None:
        raw_call("close", {"windows": [W]})
        time.sleep(0.5)
        if W in visibles():
            subprocess.run(["osascript", "-e", f'tell application "Safari" to close window id {W}'])
    print("Windows identical to before:", visibles() == avant)
    proc.stdin.close()
    proc.wait(timeout=10)
    httpd.shutdown()

if OUT:
    with open(OUT, "w") as f:
        json.dump(rows, f, indent=1, ensure_ascii=False)
print(f"{sum(r.get('within', False) for r in rows)}/{len(rows)} scenarios within their target")
