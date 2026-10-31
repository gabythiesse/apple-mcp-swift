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
    return {n["id"]: n for n in call("lire_notes", {"ids": ids, **kw})["notes"]}


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
    check(all(a["readOnlyHint"] == (n in {"dossiers", "notes", "lire_notes", "tags", "ouvrir_note"}) for n, a in ann.items()), "readOnlyHint sur les lectures seulement")
    check(all(a["destructiveHint"] == n.startswith("supprimer_") for n, a in ann.items()), "destructiveHint sur les suppressions seulement")
    check(not any(a["openWorldHint"] for a in ann.values()), "openWorldHint false partout")
    check(rpc("methode/inconnue").get("error", {}).get("code") == -32601, "méthode inconnue → -32601")
    check("outil inconnu" in call("outil_inexistant", expect_error=True), "outil inconnu → isError")

    print("== Dossiers")
    d = call("creer_dossier", {"nom": PREFIX, "sous_dossiers": ["[mcp-test] sous"]})
    F, SF = d["id"], d["sous_dossiers"][0]["id"]
    check(F.startswith("d") and SF.startswith("d"), f"dossier et sous-dossier créés : {F} {SF}")
    ds = [x for c in call("dossiers", {"nom_contient": PREFIX})["comptes"] for x in c["dossiers"]]
    check([x["id"] for x in ds] == [F], f"dossiers filtrés : {len(ds)}")
    sub = [x for c in call("dossiers", {"nom_contient": "[mcp-test] sous"})["comptes"] for x in c["dossiers"] if x["id"] == SF]
    check(sub and sub[0].get("parent_id") == F, "sous-dossier rattaché au parent")
    call("renommer_dossier", {"id": SF, "nom": "[mcp-test] sous renommé"})
    check(any(x["id"] == SF for c in call("dossiers", {"nom_contient": "[mcp-test] sous renommé"})["comptes"] for x in c["dossiers"]), "sous-dossier renommé")

    print("== Création en lot")
    res = call("creer_notes", {"notes": [
        {"titre": "[mcp-test] A", "texte": "intro zqneedle\n- puce 1\n- puce 2\n1. un\n2. deux\n**gras** et *ital*", "dossier_id": F},
        {"titre": "[mcp-test] B", "html": "<div><b>html</b> direct</div>", "dossier_id": F},
        {"titre": "[mcp-test] C", "texte": "dans le sous-dossier", "dossier_id": SF},
        {"titre": "[mcp-test] D", "dossier_id": F},
        {"titre": "", "dossier_id": F},
    ]})
    r = res["resultats"]
    check(res["crees"] == 4 and res["echecs"] == 1, f"4 créées, 1 refusée : {res['crees']}/{res['echecs']}")
    A, B, C, D = (x.get("id") for x in r[:4])
    created_notes += [x for x in (A, B, C, D) if x]
    check(all(x and x.startswith("n") for x in (A, B, C, D)), "identifiants courts renvoyés")
    check(r[2].get("dossier_id") == SF, "C dans le sous-dossier")

    print("== Lecture et recherche")
    ls = call("notes", {"dossier_id": F})
    check(ls["total"] == 4, f"notes du dossier + sous-dossier : {ls['total']}")
    check({n["id"]: n["dossier_id"] for n in ls["notes"]}.get(C) == SF, "C attribuée au sous-dossier")
    check(call("notes", {"dossier_id": F, "sous_dossiers": False})["total"] == 3, "sans sous-dossiers : 3")
    check([n["id"] for n in call("notes", {"dossier_id": F, "texte": "zqneedle"})["notes"]] == [A], "recherche plein texte")
    check(call("notes", {"dossier_id": F, "modifiees_depuis": str(today)})["total"] == 4, "filtre modifiees_depuis")
    check(call("notes", {"dossier_id": F, "modifiees_avant": str(today)})["total"] == 0, "filtre modifiees_avant")
    p = call("notes", {"dossier_id": F, "limite": 2})
    check(len(p["notes"]) == 2 and "tronque" in p, "limite + tronque")
    check(call("notes", {"dossier_id": F, "tag": "mcptest-introuvable"})["total"] == 0, "filtre tag (base)")
    check(call("notes", {"dossier_id": F, "epinglees": True})["total"] == 0, "filtre epinglees (base)")
    lu = lire([A, B])
    check(lu[A]["titre"] == "[mcp-test] A" and "puce 2" in lu[A]["contenu"] and "zqneedle" in lu[A]["contenu"], "texte relu")
    check(lu[A]["contenu"].count("[mcp-test] A") == 1, "titre non dupliqué")
    hb = lire([B], format="html")[B]["contenu"]
    check("<b>html</b>" in hb, "HTML relu")
    tg = call("tags", {"dossier_id": F})
    check(tg == {"tags": []}, f"tags du dossier de test : {tg}")

    print("== Pièces jointes")
    pj = call("ajouter_pieces_jointes", {"pieces": [{"note_id": A, "chemin": PNG}, {"note_id": A, "chemin": TXT},
                                                    {"note_id": A, "chemin": "/chemin/absent.png"}]})
    check(pj["ajoutees"] == 2 and not pj["resultats"][2]["ok"], f"2 PJ ajoutées, fichier absent refusé : {pj['ajoutees']}")
    P1, P2 = pj["resultats"][0].get("id"), pj["resultats"][1].get("id")
    la = lire([A], format="html")[A]
    check(len(la.get("pieces_jointes", [])) == 2, f"PJ dédoublonnées : {la.get('pieces_jointes')}")
    check("base64" not in la["contenu"], "base64 retiré du HTML")
    ex = call("exporter_pieces_jointes", {"dossier": EXPORT, "note_ids": [A]})
    check(ex["exportees"] == 2 and len(os.listdir(EXPORT)) == 2, f"export : {sorted(os.listdir(EXPORT)) if os.path.isdir(EXPORT) else ex}")
    ex2 = call("exporter_pieces_jointes", {"dossier": EXPORT, "ids": [P1]})
    check(ex2["exportees"] == 0 and "existe déjà" in ex2["resultats"][0].get("erreur", ""), "export : jamais d'écrasement")
    check(not any(x.startswith(".notes-mcp") for x in os.listdir(EXPORT)), "dossier de transit retiré")
    check("supprimer_pieces_jointes" not in ann, "pas d'outil de suppression de PJ (non supporté par Notes)")

    print("== Modification en lot")
    res = call("modifier_notes", {"modifications": [
        {"id": D, "titre": "[mcp-test] D2"},
        {"id": B, "texte": "remplacé"},
        {"id": C, "ajouter_texte": "- ajout en fin"},
        {"id": A, "dossier_id": SF},
        {"id": "n999999999", "titre": "x"},
    ]})
    check(res["modifiees"] == 4 and res["echecs"] == 1, f"4 modifiées, 1 inconnue : {res['modifiees']}/{res['echecs']}")
    lu = lire([A, B, C, D])
    check(lu[D]["titre"] == "[mcp-test] D2", "titre changé")
    check(len(lu[A].get("pieces_jointes", [])) == 2 and lu[A]["dossier_id"] == SF, f"note avec PJ déplacée, PJ intacte : {lu[A].get('pieces_jointes')}")
    check(lu[B]["titre"] == "[mcp-test] B" and "remplacé" in lu[B]["contenu"] and "direct" not in lu[B]["contenu"], "contenu remplacé, titre gardé")
    check(lu[C]["contenu"].rstrip().endswith("ajout en fin") and "sous-dossier" in lu[C]["contenu"], "ajout en fin")
    res = call("modifier_notes", {"modifications": [{"id": A, "ajouter_texte": "x"}]})
    check(res["echecs"] == 1 and "pièces jointes" in res["resultats"][0]["erreur"], "contenu d'une note avec PJ protégé")
    call("ouvrir_note", {"id": A})

    print("== Corbeille et restauration")
    check(call("supprimer_notes", {"ids": [B]})["supprimees"] == 1, "B dans la corbeille")
    check(B not in [n["id"] for n in call("notes", {"dossier_id": F})["notes"]], "B hors du dossier")
    check(lire([B])[B]["dossier"] in ("Recently Deleted", "Supprimées récemment"), "B dans « Supprimées récemment »")
    res = call("modifier_notes", {"modifications": [{"id": B, "dossier_id": F}]})
    check(res["modifiees"] == 1 and lire([B])[B]["dossier_id"] == F, "B restaurée")
    res = call("supprimer_notes", {"ids": [B], "definitif": True})
    check(res["supprimees"] == 1, "B purgée")
    check(lire([B])[B].get("ok") is False, "B introuvable après purge")
    created_notes.remove(B)

    print("== Suppression du dossier")
    sd = call("supprimer_dossier", {"id": F})
    check(sd["notes_en_corbeille"] == 3 and sd["sous_dossiers_supprimes"] == 1, f"dossier supprimé : {sd}")
    F = None
finally:
    print("== Nettoyage")
    try:
        if F:
            call("supprimer_dossier", {"id": F})
        if created_notes:
            call("supprimer_notes", {"ids": created_notes, "definitif": True})
    except Exception as e:  # noqa: BLE001
        print("  nettoyage :", e)
    restes = call("notes", {"texte": "[mcp-test]", "supprimees": True})
    check(restes["total"] == 0, f"aucune note [mcp-test] restante, corbeille comprise ({restes['total']})")
    ds = [x for c in call("dossiers", {"nom_contient": "MCP-TEST-"})["comptes"] for x in c["dossiers"]]
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
