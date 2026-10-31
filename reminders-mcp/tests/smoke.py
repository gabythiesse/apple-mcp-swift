#!/usr/bin/env python3 -I
"""Test de bout en bout du serveur MCP Rappels.

Lance le binaire, appelle chaque outil une fois sur des données de test marquées
(listes MCP-TEST-<horodatage>, rappels [mcp-test]), puis supprime tout par identifiant
et vérifie qu'il ne reste rien. Les lectures sont toujours filtrées sur les listes de test.
Usage : python3 -I tests/smoke.py [chemin du binaire]
"""
import base64
import datetime as dt
import json
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BIN = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, ".build/release/RemindersMCP")
TS = int(time.time())
PREFIX = f"MCP-TEST-{TS}"
PNG = os.path.join(ROOT, "tests", "pixel.png")

proc = subprocess.Popen([BIN], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
next_id = 0
fails = []


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
    if res.get("isError"):
        if not expect_error:
            check(False, f"{name} a échoué : {text}")
        return text
    if expect_error:
        check(False, f"{name} aurait dû échouer : {text[:200]}")
    data = json.loads(text)
    print(f"   {name} ({ms} ms)")
    return data


def check(cond, label):
    print(("  ✓ " if cond else "  ✗ ") + label)
    if not cond:
        fails.append(label)


def by_title(items, title):
    return next((r for r in items if r["titre"] == title), None)


def lire(listes, **kw):
    return call("rappels", {"liste_ids": listes, **kw})["rappels"]


today = dt.date.today()
tomorrow = today + dt.timedelta(days=1)
yesterday = today - dt.timedelta(days=1)
created_lists = []  # (id, est_groupe) ; nettoyées à la fin quoi qu'il arrive

try:
    print("== Protocole")
    init = rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "smoke", "version": "1"}})
    check(init["result"]["serverInfo"]["name"] == "rappels", "initialize")
    rpc("notifications/initialized", notify=True)
    check(rpc("ping")["result"] == {}, "ping")
    tools = [t["name"] for t in rpc("tools/list")["result"]["tools"]]
    check(len(tools) == 14, f"tools/list : {len(tools)} outils")
    check(rpc("methode/inconnue").get("error", {}).get("code") == -32601, "méthode inconnue → -32601")
    check("outil inconnu" in call("outil_inexistant", expect_error=True), "outil inconnu → isError")

    print("== Listes et groupes")
    A = call("creer_liste", {"nom": f"{PREFIX}-A", "couleur": "vert"})["id"]; created_lists.append((A, False))
    B = call("creer_liste", {"nom": f"{PREFIX}-B"})["id"]; created_lists.append((B, False))
    G = call("creer_liste", {"nom": f"{PREFIX}-GROUPE", "groupe": True})["id"]; created_lists.append((G, True))
    C = call("creer_liste", {"nom": f"{PREFIX}-C", "groupe_id": G}); created_lists.insert(0, (C["id"], False))
    check("avertissement" not in C, "liste créée dans un groupe")
    C = C["id"]
    ls = {l["id"]: l for l in call("listes", {"nom_contient": PREFIX})["listes"]}
    check(len(ls) == 4, f"listes filtrées : {len(ls)} sur 4")
    check(ls.get(G, {}).get("groupe") is True, "groupe marqué groupe: true")
    check(ls.get(C, {}).get("groupe_id") == G, "liste C dans le groupe")
    check(ls.get(A, {}).get("couleur") == "#34C759", f"couleur de A : {ls.get(A, {}).get('couleur')}")
    call("modifier_liste", {"id": A, "nom": f"{PREFIX}-A2", "couleur": "#FF9500"})
    call("modifier_liste", {"id": B, "groupe_id": G})
    check(call("listes", {"nom_contient": f"{PREFIX}-B"})["listes"][0].get("groupe_id") == G, "B rangée dans le groupe")
    call("modifier_liste", {"id": B, "groupe_id": ""})
    check("groupe_id" not in call("listes", {"nom_contient": f"{PREFIX}-B"})["listes"][0], "B sortie du groupe")
    call("modifier_liste", {"id": G, "nom": f"{PREFIX}-GROUPE2"})
    ls = {l["id"]: l for l in call("listes", {"nom_contient": PREFIX})["listes"]}
    check(ls[A]["nom"] == f"{PREFIX}-A2" and ls[A].get("couleur") == "#FF9500", "A renommée et recolorée")
    check(ls[G]["nom"] == f"{PREFIX}-GROUPE2" and ls[G].get("groupe") is True, "groupe renommé")

    print("== Sections")
    S1 = call("creer_section", {"liste_id": A, "nom": "[mcp-test] S1"})["id"]
    S2 = call("creer_section", {"liste_id": A, "nom": "[mcp-test] S2"})["id"]
    secs = call("sections", {"liste_id": A})["sections"]
    check({s["id"] for s in secs} == {S1, S2}, f"sections de A : {len(secs)}")

    print("== Création en lot")
    res = call("creer_rappels", {"rappels": [
        {"titre": "[mcp-test] complet", "liste_id": A, "notes": "note de test", "echeance": f"{tomorrow}T09:30",
         "priorite": "haute", "drapeau": True, "tags": ["mcptest", "#autre"], "url": "https://example.com",
         "section_id": S1, "recurrence": {"frequence": "semaine", "jours": ["lundi", "jeudi"], "occurrences": 3},
         "alarmes": [{"date": f"{tomorrow}T09:00"}, {"minutes_avant": 15},
                     {"lieu": "Tour Eiffel", "latitude": 48.8584, "longitude": 2.2945, "quand": "depart"}],
         "sous_taches": [{"titre": "[mcp-test] st1"}, {"titre": "[mcp-test] st2", "echeance": str(tomorrow)}]},
        {"titre": "[mcp-test] simple", "liste_id": A, "echeance": str(yesterday)},
        {"titre": "[mcp-test] section2", "liste_id": A, "section_id": S1},
        {"titre": "", "liste_id": A},
    ]})
    r0 = res["resultats"]
    check(res["crees"] == 3 and res["echecs"] == 1, f"3 créés, 1 refusé (titre vide) : {res['crees']}/{res['echecs']}")
    check(all("avertissement" not in r for r in r0[:3]), "aucun avertissement ReminderKit : " + str([r.get("avertissement") for r in r0[:3] if "avertissement" in r]))
    check(len(r0[0].get("sous_taches", [])) == 2 and all(s["ok"] for s in r0[0]["sous_taches"]), "2 sous-tâches créées")
    COMPLET, SIMPLE, SEC2 = r0[0]["id"], r0[1]["id"], r0[2]["id"]
    ST1, ST2 = (s["id"] for s in r0[0]["sous_taches"])

    print("== Lecture")
    rs = lire([A], statut="tous")
    c = by_title(rs, "[mcp-test] complet") or {}
    check(c.get("echeance") == f"{tomorrow}T09:30", f"échéance : {c.get('echeance')}")
    check(c.get("priorite") == "haute" and c.get("notes") == "note de test", "priorité, notes")
    check(c.get("drapeau") is True and c.get("tags") == ["autre", "mcptest"], f"drapeau, tags : {c.get('tags')}")
    check(c.get("url") == "https://example.com", f"URL : {c.get('url')}")
    check(c.get("section_id") == S1, f"section : {c.get('section')}")
    check(c.get("recurrence", {}).get("jours") == ["lundi", "jeudi"], f"récurrence : {c.get('recurrence')}")
    check(len(c.get("alarmes", [])) == 3, f"alarmes : {c.get('alarmes')}")
    check(c.get("nb_sous_taches") == 2, f"nb_sous_taches : {c.get('nb_sous_taches')}")
    check(by_title(rs, "[mcp-test] st1", ).get("parent_id") == COMPLET, "sous-tâche reliée au parent")
    check((by_title(rs, "[mcp-test] section2") or {}).get("section_id") == S1, "2e rappel rangé dans S1")
    check(c.get("section_id") == S1, "le 1er rappel reste dans S1 après le 2e")
    check([r["titre"] for r in lire([A], vue="en_retard")] == ["[mcp-test] simple"], "vue en_retard")
    check("[mcp-test] simple" in [r["titre"] for r in lire([A], vue="aujourdhui")], "vue aujourdhui inclut les retards")
    check("[mcp-test] complet" in [r["titre"] for r in lire([A], vue="semaine")], "vue semaine")
    check(len(lire([A], vue="programmes")) == 3, "vue programmes (3 avec échéance)")
    check([r["titre"] for r in lire([A], vue="drapeau")] == ["[mcp-test] complet"], "vue drapeau")
    check([r["titre"] for r in lire([A], texte="NOTE DE TÈST")] == ["[mcp-test] complet"], "recherche texte (casse, accents)")
    check([r["titre"] for r in lire([A], tag="#mcptest")] == ["[mcp-test] complet"], "filtre tag")
    check({r["id"] for r in lire([A], parent_id=COMPLET)} == {ST1, ST2}, "filtre parent_id")
    check(len(lire([A], echeance_apres=str(today))) == 2, "filtre echeance_apres")
    check(len(lire([A], echeance_avant=str(today))) == 1, "filtre echeance_avant")
    check(len(lire([A], sans_echeance=True)) == 2, "filtre sans_echeance")
    page = call("rappels", {"liste_ids": [A], "limite": 2})
    check(page["total"] == 5 and len(page["rappels"]) == 2 and "tronque" in page, "limite + total")
    tg = {t["tag"]: t["nb"] for t in call("tags", {"liste_ids": [A]})["tags"]}
    check(tg == {"mcptest": 1, "autre": 1}, f"tags : {tg}")

    print("== Modification en lot")
    res = call("modifier_rappels", {"modifications": [
        {"id": SIMPLE, "titre": "[mcp-test] simple modifié", "echeance": f"{tomorrow}T18:00", "drapeau": True,
         "ajouter_tags": ["x"], "url": "https://example.org", "section_id": S2, "priorite": "basse"},
        {"id": COMPLET, "retirer_tags": ["autre"], "url": "", "section_id": "", "drapeau": False,
         "recurrence": None, "alarmes": []},
        {"id": SEC2, "parent_id": COMPLET},
        {"id": ST1, "parent_id": ""},
        {"id": "00000000-0000-0000-0000-000000000000", "titre": "x"},
    ]})
    check(res["modifies"] == 4 and res["echecs"] == 1, f"4 modifiés, 1 id inconnu refusé : {res['modifies']}/{res['echecs']} {[r.get('erreur') for r in res['resultats'] if not r['ok']]}")
    rs = lire([A], statut="tous")
    s = by_title(rs, "[mcp-test] simple modifié") or {}
    check(s.get("echeance") == f"{tomorrow}T18:00" and s.get("alarmes") == [{"date": f"{tomorrow}T18:00"}], f"échéance + alerte auto : {s.get('alarmes')}")
    check(s.get("drapeau") is True and s.get("tags") == ["x"] and s.get("url") == "https://example.org", "drapeau, tag, URL ajoutés")
    check(s.get("section_id") == S2 and s.get("priorite") == "basse", "section S2, priorité basse")
    c = by_title(rs, "[mcp-test] complet") or {}
    check(c.get("tags") == ["mcptest"] and "url" not in c and "drapeau" not in c, f"tag retiré, URL retirée, drapeau retiré : {c.get('tags')}, {c.get('url')}")
    check("section_id" not in c, f"sortie de section : {c.get('section')}")
    check("recurrence" not in c and "alarmes" not in c, f"récurrence et alarmes retirées : {c.get('recurrence')} {c.get('alarmes')}")
    check((by_title(rs, "[mcp-test] section2") or {}).get("parent_id") == COMPLET, "rappel rattaché comme sous-tâche")
    st1 = by_title(rs, "[mcp-test] st1") or {}
    check("parent_id" not in st1 and st1.get("liste_id") == A, "sous-tâche détachée, toujours dans A")

    print("== Déplacements")
    res = call("modifier_rappels", {"modifications": [{"id": COMPLET, "liste_id": B}, {"id": ST1, "liste_id": B}]})
    check(res["modifies"] == 2, f"déplacements : {[r.get('erreur') for r in res['resultats'] if not r['ok']]}")
    inB = {r["titre"]: r for r in lire([B], statut="tous")}
    check({"[mcp-test] complet", "[mcp-test] st2", "[mcp-test] section2", "[mcp-test] st1"} <= set(inB), f"parent + sous-tâches + rappel simple dans B : {sorted(inB)}")
    check(inB.get("[mcp-test] st2", {}).get("parent_id") == COMPLET, "les sous-tâches gardent leur parent")
    res = call("modifier_rappels", {"modifications": [{"id": ST2, "liste_id": A}]})
    st2 = by_title(lire([A], statut="tous"), "[mcp-test] st2") or {}
    check(res["modifies"] == 1 and "parent_id" not in st2, "sous-tâche seule déplacée (détachée)")
    res = call("modifier_rappels", {"modifications": [{"id": ST2, "parent_id": COMPLET}]})
    st2 = by_title(lire([B], statut="tous"), "[mcp-test] st2") or {}
    check(res["modifies"] == 1 and st2.get("parent_id") == COMPLET, "rattachement à un parent d'une autre liste")

    print("== Image")
    with open(PNG, "wb") as f:
        f.write(base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="))
    im = call("ajouter_image", {"id": SIMPLE, "chemin": PNG})
    check(im.get("largeur") == 1, "image ajoutée")
    check((by_title(lire([A]), "[mcp-test] simple modifié") or {}).get("images") == 1, "image relue")
    os.remove(PNG)

    print("== Terminer, rouvrir")
    call("terminer_rappels", {"ids": [SIMPLE]})
    check("[mcp-test] simple modifié" in [r["titre"] for r in lire([A], vue="termines_recents")], "terminé (vue termines_recents)")
    call("terminer_rappels", {"ids": [SIMPLE], "termine": False})
    check("[mcp-test] simple modifié" in [r["titre"] for r in lire([A])], "rouvert")

    print("== Suppressions")
    call("supprimer_section", {"id": S2})
    check([s["id"] for s in call("sections", {"liste_id": A})["sections"]] == [S1], "section supprimée")
    check("section_id" not in (by_title(lire([A]), "[mcp-test] simple modifié") or {}), "son rappel reste dans la liste, hors section")
    res = call("supprimer_rappels", {"ids": [COMPLET]})["resultats"][0]
    check(res["ok"] and res.get("sous_taches_supprimees") == 2, f"parent supprimé avec 2 sous-tâches : {res}")
    left = {r["titre"] for r in lire([B], statut="tous")}
    check(left == {"[mcp-test] st1"}, f"il reste seulement st1 dans B : {sorted(left)}")
    check("contient" in call("supprimer_liste", {"id": A}, expect_error=True), "liste non vide refusée sans force")
    check("contient" in call("supprimer_liste", {"id": G}, expect_error=True), "groupe non vide refusé")
finally:
    print("== Nettoyage")
    for lid, is_group in sorted(created_lists, key=lambda x: x[1]):  # listes d'abord, groupe ensuite
        try:
            call("supprimer_liste", {"id": lid, "force": True})
        except Exception as e:  # noqa: BLE001
            print("  nettoyage", lid, e)
    restant = call("listes", {"nom_contient": PREFIX})["listes"]
    check(restant == [], f"aucune liste de test restante ({len(restant)})")
    proc.stdin.close()
    proc.wait(timeout=10)

print()
print("✓ TOUT PASSE" if not fails else f"✗ {len(fails)} échec(s) :\n  - " + "\n  - ".join(fails))
sys.exit(1 if fails else 0)
