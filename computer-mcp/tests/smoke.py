#!/usr/bin/env python3 -I
"""End-to-end test of the Computer MCP server, on TextEdit.

Launches TextEdit (or uses it if already running, without touching its documents), answers its Open panel,
types into a new document, clicks, drags, scrolls, closes it through File > Close and answers "Supprimer" to the
save sheet, then does it again with a watch_dialogs rule, and quits TextEdit if the test launched it.
Nothing is saved: the documents are deleted by TextEdit itself. Checks that the app in front at the end is the one
that was in front at the start. Prints the median duration of every tool.
Runs through the AppleMCP launcher, whose Accessibility permission the server uses.
Usage: python3 -I computer-mcp/tests/smoke.py [launcher or binary]
"""
import json
import os
import re
import statistics
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LAUNCHER = os.path.join(os.path.dirname(ROOT), "bin", "AppleMCP")
target = sys.argv[1] if len(sys.argv) > 1 else LAUNCHER
cmd = [target, "computer"] if os.path.basename(target) == "AppleMCP" else [target]
TS = int(time.time())
MARK = f"MCP-TEST-{TS}"

proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
next_id = 0
fails = []
durations = {}


def rpc(method, params=None):
    global next_id
    next_id += 1
    msg = {"jsonrpc": "2.0", "id": next_id, "method": method}
    if params is not None:
        msg["params"] = params
    proc.stdin.write(json.dumps(msg) + "\n")
    proc.stdin.flush()
    line = proc.stdout.readline()
    if not line:
        raise RuntimeError("the server stopped")
    return json.loads(line)


TRACE = os.environ.get("TRACE")


def call(name, args=None, expect_error=False, quiet=False):
    t0 = time.time()
    res = rpc("tools/call", {"name": name, "arguments": args or {}})["result"]
    ms = (time.time() - t0) * 1000
    durations.setdefault(name, []).append(ms)
    texts = [c["text"] for c in res["content"] if c["type"] == "text"]
    text = "\n".join(texts)
    if res.get("isError"):
        if not expect_error:
            check(False, f"{name} failed: {text[:300]}")
        return res
    if expect_error:
        check(False, f"{name} should have failed: {text[:200]}")
    if not quiet:
        print(f"   {name} ({int(ms)} ms): {text.splitlines()[0][:110] if text else ''}")
        if TRACE:
            r2 = rpc("tools/call", {"name": "_cg", "arguments": {}})["result"]
            print("      trace: " + r2["content"][0]["text"].splitlines()[0])
    return res


def text_of(res):
    return "\n".join(c["text"] for c in res["content"] if c["type"] == "text")


def check(cond, label):
    print(("  ✓ " if cond else "  ✗ ") + label)
    if not cond:
        fails.append(label)


def front_app():
    t = text_of(call("windows", {}, quiet=True))
    m = re.search(r"^\* (.+?) pid=", t, re.M)
    return m.group(1) if m else None


def textedit_pid():
    r = subprocess.run(["pgrep", "-x", "TextEdit"], capture_output=True, text=True)
    return r.stdout.split()[0] if r.stdout.strip() else None


def ref_of(text, pattern):
    m = re.search(r"(a\d+) " + pattern, text)
    return m.group(1) if m else None


def te_windows():
    """{title: ref} of TextEdit's windows"""
    t = text_of(call("windows", {"app": "TextEdit"}, quiet=True))
    return {m.group(2): m.group(1) for m in re.finditer(r'^\s+(a\d+) "(.*?)"', t, re.M)}


def new_document(how):
    """Creates an untitled TextEdit document; returns (its window title, ref of its text area)."""
    before = te_windows()
    if how == "panel":
        r = call("answer_dialog", {"app": "TextEdit", "button": "Nouveau document"})
        check("closed" in text_of(r), "Open panel answered with [Nouveau document]")
    else:
        call("menu", {"app": "TextEdit", "path": "Fichier > Nouveau"})
    for _ in range(25):
        new = {k: v for k, v in te_windows().items() if k not in before and k != "Ouvrir"}
        if new:
            title, wref = next(iter(new.items()))
            area = ref_of(text_of(call("find", {"app": "TextEdit", "window": wref, "role": "textarea"}, quiet=True)), "textArea")
            if area:
                return title, area
        time.sleep(0.2)
    return None, None


rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "smoke", "version": "1"}})
tools = [t["name"] for t in rpc("tools/list")["result"]["tools"]]
expected = ["screenshot", "windows", "find", "dialogs", "click", "type", "press", "scroll", "drag", "move",
            "answer_dialog", "watch_dialogs", "app", "menu"]
check(tools == expected, f"{len(tools)} tools listed")

launched = False
front0 = None
try:
    print("== look")
    front0 = front_app()
    check(front0 is not None, f"windows: front app is {front0}")
    r = call("dialogs", {})
    check(not r.get("isError"), "dialogs answers")
    r = rpc("tools/call", {"name": "screenshot", "arguments": {"scale": 0.5}})["result"]
    if r.get("isError"):
        check("Screen Recording" in text_of(r), "screenshot refuses in one sentence without the Screen Recording permission")
    else:
        img = [c for c in r["content"] if c["type"] == "image"]
        check(bool(img) and img[0]["mimeType"] == "image/png" and len(img[0]["data"]) > 1000, "screenshot returns a PNG")
    call("find", {"app": "TextEdit"}, expect_error=textedit_pid() is None, quiet=True)
    check(True, "find on a stopped app refuses" if textedit_pid() is None else "find on TextEdit")

    print("== TextEdit")
    was_running = textedit_pid() is not None
    r = call("app", {"app": "TextEdit"})
    launched = not was_running
    check(textedit_pid() is not None, "TextEdit is running")
    d = text_of(call("dialogs", {"app": "TextEdit"}))
    title, area = new_document("panel" if "panel" in d and "Nouveau document" in d else "menu")
    check(area is not None, f"new document \"{title}\", text area {area}")

    print("== type, press, click, drag, scroll, move")
    r = call("type", {"ref": area, "text": f"Bonjour {MARK}\nligne deux éàü"})
    check(MARK in text_of(r) and "deux" in text_of(r), "type: text with accents and a new line is in the document")
    r = call("press", {"ref": area, "keys": ["cmd+a"]})
    r = call("type", {"ref": area, "text": f"{MARK} remplacé"})
    t = text_of(call("find", {"ref": area}, quiet=True))
    check(f'"{MARK} remplacé"' in t, "press cmd+a then type replaces the content")
    m = re.search(r"@(-?\d+),(-?\d+) (\d+)x(\d+)", t)
    x, y = (int(m.group(1)) + 12, int(m.group(2)) + 10) if m else (0, 0)
    r = call("click", {"ref": area, "count": 2})
    check("double-clicked" in text_of(r) and "CGEvent" in text_of(r), "click count 2 is a real double click")
    r = call("drag", {"from_x": x, "from_y": y, "to_x": x + 140, "to_y": y, "app": "TextEdit"})
    check("dragged" in text_of(r), "drag across the text")
    r = call("scroll", {"ref": area, "dy": 3})
    check("scrolled" in text_of(r), "scroll over the text area")
    r = call("move", {"ref": area})
    check("textArea" in text_of(r), "move: the pointer is over the text area (TextEdit brought to the front if hidden)")
    call("app", {"app": front0, "action": "activate"}, quiet=True)   # move laisse TextEdit devant : on rend la main pour la suite
    r = call("click", {"app": "TextEdit", "title": "Gras", "role": "checkbox"})
    check("AXPress" in text_of(r), "click by title in an app uses the Accessibility press (format bar: Bold)")
    r = call("click", {"app": "TextEdit", "title": "MCP-inexistant"}, expect_error=True, quiet=True)
    check("nothing titled" in text_of(r), "click on a title that does not exist says so")
    r = call("type", {"text": "x"}, expect_error=True, quiet=True)
    check("give app" in text_of(r), "type without app or ref refuses (never types into whatever is in front)")

    print("== File > Close, answer_dialog")
    r = call("menu", {"app": "TextEdit", "path": "Fichier"})
    check("Fermer" in text_of(r), "menu lists File")
    r = call("menu", {"app": "TextEdit", "path": "Fichier > Fermer"})
    check("new dialog" in text_of(r) and "Supprimer" in text_of(r), "File > Close reports the save sheet and its buttons")
    r = call("answer_dialog", {"app": "TextEdit", "button": "Supprimer"})
    check("closed" in text_of(r), "answer_dialog [Supprimer] closes the sheet")
    t = text_of(call("windows", {"app": "TextEdit"}, quiet=True))
    check(f'"{title}"' not in t, "the document is gone")

    print("== watch_dialogs")
    title, area = new_document("menu")
    check(area is not None, f"second document \"{title}\"")
    call("type", {"ref": area, "text": MARK})
    r = call("watch_dialogs", {"rules": [{"app": "TextEdit", "contains": "nouveau document", "button": "Supprimer"}], "mode": "replace"})
    check("watching 1 rule" in text_of(r), "watch_dialogs: rule set")
    call("press", {"app": "TextEdit", "keys": "cmd+w"})
    r = call("watch_dialogs", {"wait": 8})
    check("✓ TextEdit" in text_of(r) and "[Supprimer]" in text_of(r), "the sheet was answered by the rule, with no call")
    r = call("watch_dialogs", {"mode": "clear"})
    check("not watching" in text_of(r), "watch_dialogs: cleared")
    t = text_of(call("windows", {"app": "TextEdit"}, quiet=True))
    check(f'"{title}"' not in t, "the second document is gone")
finally:
    if launched and textedit_pid():
        r = call("app", {"app": "TextEdit", "action": "quit"})
        if "asks" in text_of(r):
            call("answer_dialog", {"app": "TextEdit", "button": "Supprimer"})
        for _ in range(30):
            if not textedit_pid():
                break
            time.sleep(0.1)
        check(textedit_pid() is None, "TextEdit quit, nothing left")
    front1 = front_app()
    check(front1 == front0, f"the app in front at the end is the one at the start ({front0})")
    proc.stdin.close()
    proc.wait(timeout=5)

print("\nmedian durations (ms):")
for name in expected:
    if name in durations:
        d = durations[name]
        print(f"  {name:14} {statistics.median(d):7.0f}  ({len(d)} calls)")
print("\n" + ("✓ ALL OK" if not fails else f"✗ {len(fails)} FAILURES:\n  " + "\n  ".join(fails)))
sys.exit(1 if fails else 0)
