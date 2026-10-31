#!/usr/bin/env python3 -I
"""First call to each installed MCP server: triggers the macOS permission prompts (once and for all).
Only reads container names (lists, calendars, mailboxes, folders, groups, tabs), never any content.
Usage: python3 -I first-call.py [server names…]"""
import json, subprocess, sys, time, os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LAUNCHER = f"{ROOT}/bin/AppleMCP"
# server -> read-only tool that lists containers
SERVERS = {
    "reminders": "list_lists",
    "calendar":  "list_calendars",
    "contacts":  "list_groups",
    "mail":      "list_mailboxes",
    "notes":     "list_folders",
    "safari":    "list_tabs",
}
wanted = sys.argv[1:] or list(SERVERS)
all_ok = True
for name in wanted:
    tool = SERVERS[name]
    p = subprocess.Popen([LAUNCHER, name], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1)
    def rpc(i, method, params):
        p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": i, "method": method, "params": params}) + "\n"); p.stdin.flush()
        return json.loads(p.stdout.readline())
    rpc(1, "initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "first-call", "version": "1"}})
    t0 = time.time()
    print(f"→ {name:10s}: if macOS asks for permission, click \"Allow\"…", flush=True)
    r = rpc(2, "tools/call", {"name": tool, "arguments": {}})["result"]
    text = r["content"][0]["text"]
    failed = r.get("isError") or any(m in text.lower() for m in ("denied", "not authorized", "permission", "-1743", "not permitted"))
    all_ok &= not failed
    print(("  ✗ " if failed else "  ✓ ") + name + (f": {text[:160]}" if failed else f" ({int((time.time()-t0)*1000)} ms)"), flush=True)
    p.stdin.close(); p.wait(timeout=10)
print("\n✓ ALL SERVERS RESPOND" if all_ok else "\n✗ at least one server is blocked (see above)")
sys.exit(0 if all_ok else 1)
