#!/usr/bin/env python3 -I
"""Test de bout en bout du serveur MCP Notes.

Lance le binaire, appelle chaque outil sur des données de test marquées (dossier MCP-TEST-<horodatage>,
notes [mcp-test]), journalise durée et taille de chaque appel, puis supprime tout par identifiant
(purge de « Supprimées récemment » comprise) et vérifie qu'il ne reste rien.
Les lectures globales (notes, tags, dossiers) sont toujours filtrées sur le dossier de test.
Usage : python3 -I tests/smoke.py [chemin du binaire]
"""
import base64
import datetime as dt
import json
import os
import shutil
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BIN = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "bin", "NotesMCP")
TS = int(time.time())
PREFIX = f"MCP-TEST-{TS}"
TMP = os.path.join(ROOT, "tests", f"tmp-{TS}")
os.makedirs(TMP)
PNG, TXT, EXPORT = os.path.join(TMP, "pixel.png"), os.path.join(TMP, "pj.txt"), os.path.join(TMP, "export")
with open(PNG, "wb") as f:
    f.write(base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="))
with open(TXT, "w") as f:
    f.write("fichier [mcp-test]\n")

proc = subprocess.Popen([BIN], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
next_id = 0
fails, journal = [], []
T0 = time.time()


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
        raise RuntimeError("le serveur s'est arrêté")
    return json.loads(line)


def call(name, args=None, expect_error=False):
    t0 = time.time()
    res = rpc("tools/call", {"name": name, "arguments": args or {}})["result"]
    text = res["content"][0]["text"]
    ms = int((time.time() - t0) * 1000)
    journal.append((name, ms, len(text)))
    print(f"   {name} : {ms} ms, {len(text)} o")
    if res.get("isError"):
        if not expect_error:
            check(False, f"{name} a échoué : {text}")
        return text
    if expect_error:
        check(False, f"{name} aurait dû échouer : {text[:200]}")
    return json.loads(text)


def check(cond, label):
    print(("  ✓ " if cond else "  ✗ ") + label)
    if not cond:
        fails.append(label)


def lire(ids, **kw):
    return {n["id"]: n for n in call("read_notes", {"ids": ids, **kw})["notes"]}


created_notes, F = [], None
today = dt.date.today()

try:
    print("== Protocole")
    init = rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "smoke", "version": "1"}})
    check(init["result"]["serverInfo"]["name"] == "notes", "initialize")
    rpc("notifications/initialized", notify=True)
    check(rpc("ping")["result"] == {}, "ping")
    tools = rpc("tools/list")["result"]["tools"]
    check(len(tools) == 13, f"tools/list : {len(tools)} outils")
    ann = {t["name"]: t["annotations"] for t in tools}
    check(all(a["readOnlyHint"] == (n in {"list_folders", "list_notes", "read_notes", "list_tags", "open_note"}) for n, a in ann.items()), "readOnlyHint sur les lectures seulement")
    check(all(a["destructiveHint"] == n.startswith("delete_") for n, a in ann.items()), "destructiveHint sur les suppressions seulement")
    check(not any(a["openWorldHint"] for a in ann.values()), "openWorldHint false partout")
    check(rpc("methode/inconnue").get("error", {}).get("code") == -32601, "méthode inconnue → -32601")
    check("unknown tool" in call("outil_inexistant", expect_error=True), "outil inconnu → isError")

    print("== Dossiers")
    d = call("create_folder", {"name": PREFIX, "subfolders": ["[mcp-test] sous"]})
    F, SF = d["id"], d["subfolders"][0]["id"]
    check(F.startswith("d") and SF.startswith("d"), f"dossier et sous-dossier créés : {F} {SF}")
    ds = [x for c in call("list_folders", {"name_contains": PREFIX})["accounts"] for x in c["folders"]]
    check([x["id"] for x in ds] == [F], f"dossiers filtrés : {len(ds)}")
    sub = [x for c in call("list_folders", {"name_contains": "[mcp-test] sous"})["accounts"] for x in c["folders"] if x["id"] == SF]
    check(sub and sub[0].get("parent_id") == F, "sous-dossier rattaché au parent")
    call("rename_folder", {"id": SF, "name": "[mcp-test] sous renommé"})
    check(any(x["id"] == SF for c in call("list_folders", {"name_contains": "[mcp-test] sous renommé"})["accounts"] for x in c["folders"]), "sous-dossier renommé")

    print("== Création en lot")
    res = call("create_notes", {"notes": [
        {"title": "[mcp-test] A", "text": "intro zqneedle\n- puce 1\n- puce 2\n1. un\n2. deux\n**gras** et *ital*", "folder_id": F},
        {"title": "[mcp-test] B", "html": "<div><b>html</b> direct</div>", "folder_id": F},
        {"title": "[mcp-test] C", "text": "dans le sous-dossier", "folder_id": SF},
        {"title": "[mcp-test] D", "folder_id": F},
        {"title": "", "folder_id": F},
    ]})
    r = res["results"]
    check(res["created"] == 4 and res["failed"] == 1, f"4 créées, 1 refusée : {res['created']}/{res['failed']}")
    A, B, C, D = (x.get("id") for x in r[:4])
    created_notes += [x for x in (A, B, C, D) if x]
    check(all(x and x.startswith("n") for x in (A, B, C, D)), "identifiants courts renvoyés")
    check(r[2].get("folder_id") == SF, "C dans le sous-dossier")

    print("== Lecture et recherche")
    ls = call("list_notes", {"folder_id": F})
    check(ls["total"] == 4, f"notes du dossier + sous-dossier : {ls['total']}")
    check({n["id"]: n["folder_id"] for n in ls["notes"]}.get(C) == SF, "C attribuée au sous-dossier")
    check(call("list_notes", {"folder_id": F, "include_subfolders": False})["total"] == 3, "sans sous-dossiers : 3")
    check([n["id"] for n in call("list_notes", {"folder_id": F, "text": "zqneedle"})["notes"]] == [A], "recherche plein texte")
    check(call("list_notes", {"folder_id": F, "modified_since": str(today)})["total"] == 4, "filtre modified_since")
    check(call("list_notes", {"folder_id": F, "modified_before": str(today)})["total"] == 0, "filtre modified_before")
    p = call("list_notes", {"folder_id": F, "limit": 2})
    check(len(p["notes"]) == 2 and "truncated" in p, "limit + truncated")
    check(call("list_notes", {"folder_id": F, "tag": "mcptest-introuvable"})["total"] == 0, "filtre tag (base)")
    check(call("list_notes", {"folder_id": F, "pinned": True})["total"] == 0, "filtre pinned (base)")
    lu = lire([A, B])
    check(lu[A]["title"] == "[mcp-test] A" and "puce 2" in lu[A]["content"] and "zqneedle" in lu[A]["content"], "texte relu")
    check(lu[A]["content"].count("[mcp-test] A") == 1, "titre non dupliqué")
    hb = lire([B], format="html")[B]["content"]
    check("<b>html</b>" in hb, "HTML relu")
    tg = call("list_tags", {"folder_id": F})
    check(tg == {"tags": []}, f"tags du dossier de test : {tg}")

    print("== Pièces jointes")
    pj = call("add_attachments", {"attachments": [{"note_id": A, "path": PNG}, {"note_id": A, "path": TXT},
                                             {"note_id": A, "path": "/chemin/absent.png"}]})
    check(pj["added"] == 2 and not pj["results"][2]["ok"], f"2 PJ ajoutées, fichier absent refusé : {pj['added']}")
    P1, P2 = pj["results"][0].get("id"), pj["results"][1].get("id")
    la = lire([A], format="html")[A]
    check(len(la.get("attachments", [])) == 2, f"PJ dédoublonnées : {la.get('attachments')}")
    check("base64" not in la["content"], "base64 retiré du HTML")
    ex = call("export_attachments", {"destination": EXPORT, "note_ids": [A]})
    check(ex["exported"] == 2 and len(os.listdir(EXPORT)) == 2, f"export : {sorted(os.listdir(EXPORT)) if os.path.isdir(EXPORT) else ex}")
    ex2 = call("export_attachments", {"destination": EXPORT, "ids": [P1]})
    check(ex2["exported"] == 0 and "already exists" in ex2["results"][0].get("error", ""), "export : jamais d'écrasement")
    check(not any(x.startswith(".notes-mcp") for x in os.listdir(EXPORT)), "dossier de transit retiré")
    check("delete_attachments" not in ann, "pas d'outil de suppression de PJ (non supporté par Notes)")

    print("== Modification en lot")
    res = call("update_notes", {"updates": [
        {"id": D, "title": "[mcp-test] D2"},
        {"id": B, "text": "remplacé"},
        {"id": C, "append_text": "- ajout en fin"},
        {"id": A, "folder_id": SF},
        {"id": "n999999999", "title": "x"},
    ]})
    check(res["updated"] == 4 and res["failed"] == 1, f"4 modifiées, 1 inconnue : {res['updated']}/{res['failed']}")
    lu = lire([A, B, C, D])
    check(lu[D]["title"] == "[mcp-test] D2", "titre changé")
    check(len(lu[A].get("attachments", [])) == 2 and lu[A]["folder_id"] == SF, f"note avec PJ déplacée, PJ intacte : {lu[A].get('attachments')}")
    check(lu[B]["title"] == "[mcp-test] B" and "remplacé" in lu[B]["content"] and "direct" not in lu[B]["content"], "contenu remplacé, titre gardé")
    check(lu[C]["content"].rstrip().endswith("ajout en fin") and "sous-dossier" in lu[C]["content"], "ajout en fin")
    res = call("update_notes", {"updates": [{"id": A, "append_text": "x"}]})
    check(res["failed"] == 1 and "attachments" in res["results"][0]["error"], "contenu d'une note avec PJ protégé")
    call("open_note", {"id": A})

    print("== Corbeille et restauration")
    check(call("delete_notes", {"ids": [B]})["deleted"] == 1, "B dans la corbeille")
    check(B not in [n["id"] for n in call("list_notes", {"folder_id": F})["notes"]], "B hors du dossier")
    check(lire([B])[B]["folder"] in ("Recently Deleted", "Supprimées récemment"), "B dans « Supprimées récemment »")
    res = call("update_notes", {"updates": [{"id": B, "folder_id": F}]})
    check(res["updated"] == 1 and lire([B])[B]["folder_id"] == F, "B restaurée")
    res = call("delete_notes", {"ids": [B], "permanent": True})
    check(res["deleted"] == 1, "B purgée")
    check(lire([B])[B].get("ok") is False, "B introuvable après purge")
    created_notes.remove(B)

    print("== Suppression du dossier")
    sd = call("delete_folder", {"id": F})
    check(sd["notes_trashed"] == 3 and sd["subfolders_deleted"] == 1, f"dossier supprimé : {sd}")
    F = None
finally:
    print("== Nettoyage")
    try:
        if F:
            call("delete_folder", {"id": F})
        if created_notes:
            call("delete_notes", {"ids": created_notes, "permanent": True})
    except Exception as e:  # noqa: BLE001
        print("  nettoyage :", e)
    restes = call("list_notes", {"text": "[mcp-test]", "include_deleted": True})
    check(restes["total"] == 0, f"aucune note [mcp-test] restante, corbeille comprise ({restes['total']})")
    ds = [x for c in call("list_folders", {"name_contains": "MCP-TEST-"})["accounts"] for x in c["folders"]]
    check(ds == [], f"aucun dossier MCP-TEST restant ({len(ds)})")
    shutil.rmtree(TMP, ignore_errors=True)
    proc.stdin.close()
    proc.wait(timeout=10)

total = time.time() - T0
lents = [(n, ms) for i, (n, ms, _) in enumerate(journal) if ms > 500 and i > 0]
print()
print(f"Durée totale : {total:.1f} s, {len(journal)} appels")
print("Appels > 0,5 s (hors 1er) : " + (", ".join(f"{n} {ms} ms" for n, ms in lents) or "aucun"))
print("✓ TOUT PASSE" if not fails else f"✗ {len(fails)} échec(s) :\n  - " + "\n  - ".join(fails))
sys.exit(1 if fails else 0)
