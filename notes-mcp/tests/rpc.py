#!/usr/bin/env python3 -I
"""Appel ponctuel : python3 -I tests/rpc.py outil '{"arg": ...}' [--quiet] → durée, taille (et réponse sauf --quiet)."""
import json, os, subprocess, sys, time
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
p = subprocess.Popen([os.path.join(ROOT, "bin", "NotesMCP")], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
def rpc(i, m, params):
    p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": i, "method": m, "params": params}) + "\n"); p.stdin.flush()
    return json.loads(p.stdout.readline())
rpc(1, "initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "rpc", "version": "1"}})
for k in range(int(os.environ.get("REPEAT", "1"))):
    t = time.time()
    r = rpc(2 + k, "tools/call", {"name": sys.argv[1], "arguments": json.loads(sys.argv[2]) if len(sys.argv) > 2 else {}})["result"]
    txt = r["content"][0]["text"]
    print(f"{sys.argv[1]} : {int((time.time() - t) * 1000)} ms, {len(txt)} o{' ERREUR' if r.get('isError') else ''}")
    if "--quiet" not in sys.argv:
        print(txt[:2000])
p.stdin.close()
