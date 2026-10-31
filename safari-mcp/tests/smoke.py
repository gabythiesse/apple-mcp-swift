#!/usr/bin/env python3 -I
"""Test de bout en bout du serveur MCP Safari.

Lance le binaire et appelle chaque outil sur des données de test uniquement :
une fenêtre PRIVÉE (aucun historique) ouverte par le serveur, avec les pages locales
tests/mcp-test-*.html et about:blank. Les lectures de favoris, historique, liste de lecture
et groupes sont filtrées sur le marqueur « mcp-test » (résultat vide accepté).
Aucun ajout à la liste de lecture (ajouter_liste_de_lecture est validé par la sonde 10).
Ne ferme que la fenêtre de test. Journalise la durée et la taille de chaque appel.
Usage : python3 -I tests/smoke.py [chemin du binaire]
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
journal = []  # (outil, ms, octets)


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
    journal.append((name, ms, len(text.encode())))
    print(f"   {name} ({ms} ms, {len(text.encode())} o)")
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


def visibles():
    """Identifiants des fenêtres Safari visibles (identifiants seulement, aucun contenu)."""
    out = subprocess.run(["osascript", "-e", 'tell application "Safari" to get id of every window whose visible is true'],
                         capture_output=True, text=True).stdout.strip()
    return {int(x) for x in out.split(",") if x.strip()}


debut = time.time()
avant = visibles()
W = None
try:
    print("== Protocole")
    init = rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "smoke", "version": "1"}})
    check(init["result"]["serverInfo"]["name"] == "safari", "initialize")
    check(len(init["result"]["instructions"].splitlines()) <= 10, "instructions ≤ 10 lignes")
    rpc("notifications/initialized", notify=True)
    check(rpc("ping")["result"] == {}, "ping")
    tools = {t["name"]: t["annotations"] for t in rpc("tools/list")["result"]["tools"]}
    check(len(tools) == 14, f"tools/list : {len(tools)} outils")
    ro = {n for n, a in tools.items() if a["readOnlyHint"]}
    check(ro == {"onglets", "lire_page", "liste_de_lecture", "favoris", "historique", "groupes_onglets"}, f"readOnly : {sorted(ro)}")
    check([n for n, a in tools.items() if a["destructiveHint"]] == ["fermer", "supprimer_liste_de_lecture", "supprimer_historique", "supprimer_groupe_onglets"], "destructive : fermer et les trois suppressions")
    check([n for n, a in tools.items() if a["openWorldHint"]] == ["executer_js"], "openWorld : executer_js seul")
    check("ajouter_liste_de_lecture" in tools, "ajouter_liste_de_lecture présent (testé en sonde, pas en smoke)")
    check(rpc("methode/inconnue").get("error", {}).get("code") == -32601, "méthode inconnue → -32601")
    check("outil inconnu" in call("outil_inexistant", expect_error=True), "outil inconnu → isError")

    print("== Lectures filtrées sur le marqueur de test (avant)")
    h_avant = len(call("historique", {"texte": "mcp-test", "limite": 100})["pages"])

    print("== Ouvrir (fenêtre privée)")
    r = call("ouvrir", {"urls": [P1, P2], "prive": True, "attendre": True})
    W = r["fenetre_id"]
    check(W not in avant, f"fenêtre privée {W} nouvelle")
    check([o.get("titre") for o in r["onglets"]] == ["[mcp-test] page 1", "[mcp-test] page 2"], f"2 onglets chargés : {r['onglets']}")
    check([o["index"] for o in r["onglets"]] == [1, 2], "index 1 et 2")

    print("== Onglets")
    o = call("onglets", {"fenetre_id": W})
    check(o["fenetres"] == 1 and len(o["onglets"]) == 2, f"2 onglets dans la fenêtre de test : {o}")
    check(o["onglets"][0].get("actif") is True and o["onglets"][0]["url"] == P1, "onglet 1 actif, URL")
    check([x["index"] for x in call("onglets", {"fenetre_id": W, "texte": "PAGE 2"})["onglets"]] == [2], "filtre texte (casse)")
    check(len(call("onglets", {"fenetre_id": W, "limite": 1})["onglets"]) == 1, "limite")

    print("== Ouvrir dans une fenêtre existante")
    r = call("ouvrir", {"urls": ["about:blank"], "fenetre_id": W})
    check(r["onglets"][0]["index"] == 3, f"about:blank en onglet 3 : {r}")
    r = call("ouvrir", {"urls": [P2], "fenetre_id": W, "attendre": True})
    check(r["onglets"][0]["index"] == 4 and r["onglets"][0].get("titre") == "[mcp-test] page 2", f"page 2 en onglet 4 : {r}")

    print("== Naviguer")
    n = call("naviguer", {"actions": [{"fenetre_id": W, "index": 1, "url": P2}], "attendre": True})["resultats"][0]
    check(n["ok"] and n.get("titre") == "[mcp-test] page 2", f"aller à une URL : {n}")
    n = call("naviguer", {"actions": [{"fenetre_id": W, "index": 1, "action": "precedent"}], "attendre": True})["resultats"][0]
    check(n.get("titre") == "[mcp-test] page 1", f"précédent : {n}")
    n = call("naviguer", {"actions": [{"fenetre_id": W, "index": 1, "action": "suivant"}], "attendre": True})["resultats"][0]
    check(n.get("titre") == "[mcp-test] page 2", f"suivant : {n}")
    n = call("naviguer", {"actions": [{"fenetre_id": W, "index": 1, "url": P1}, {"fenetre_id": W, "index": 2, "action": "recharger"}], "attendre": True})["resultats"]
    check(all(x["ok"] for x in n) and [x.get("titre") for x in n] == ["[mcp-test] page 1", "[mcp-test] page 2"], f"lot url + recharger : {n}")
    n = call("naviguer", {"actions": [{"fenetre_id": W, "index": 2, "action": "activer"}]})["resultats"][0]
    check(n["ok"] and call("onglets", {"fenetre_id": W})["onglets"][1].get("actif") is True, "activer l'onglet 2")
    n = call("naviguer", {"actions": [{"fenetre_id": W, "index": 1, "action": "voler"}]}, expect_error=True)
    check("action inconnue" in n, "action inconnue refusée")

    print("== Lire la page")
    p = call("lire_page", {"onglets": [{"fenetre_id": W, "index": 1}, {"fenetre_id": W, "index": 2}]})["pages"]
    check("marqueur-mcp-test-1" in p[0].get("texte", "") and "marqueur-mcp-test-2" in p[1].get("texte", ""), "texte de 2 onglets en un appel")
    l = call("lire_page", {"onglets": [{"fenetre_id": W, "index": 1}], "format": "liens"})["pages"][0]
    check(l.get("liens") == [{"texte": "lien vers 2", "url": P2}], f"liens : {l.get('liens')}")
    h = call("lire_page", {"onglets": [{"fenetre_id": W, "index": 1}], "format": "html"})["pages"][0]
    check("<h1>[mcp-test] page 1</h1>" in h.get("html", ""), "html courant")
    t = call("lire_page", {"onglets": [{"fenetre_id": W, "index": 1}], "format": "html", "max_caracteres": 100})["pages"][0]
    check(t.get("tronque") is True and len(t["html"]) == 100, "troncature")
    e = call("lire_page", {"onglets": [{"fenetre_id": W, "index": 99}]})["pages"][0]
    check("erreur" in e, f"onglet inexistant → erreur par élément : {e.get('erreur', '')[:80]}")

    print("== JavaScript")
    j = call("executer_js", {"script": "document.title", "onglets": [{"fenetre_id": W, "index": 1}, {"fenetre_id": W, "index": 2}]})["resultats"]
    check([x.get("resultat") for x in j] == ["[mcp-test] page 1", "[mcp-test] page 2"], f"expression sur 2 onglets : {j}")
    j = call("executer_js", {"script": "return {n: document.links.length, h: location.protocol}", "onglets": [{"fenetre_id": W, "index": 1}]})["resultats"][0]
    check(j.get("resultat") == {"n": 1, "h": "file:"}, f"objet → JSON : {j}")
    j = call("executer_js", {"script": "document.body.innerHTML = '<p>[mcp-test] injecté</p>'; return document.body.innerText", "onglets": [{"fenetre_id": W, "index": 3}]})["resultats"][0]
    check(j.get("resultat") == "[mcp-test] injecté", f"corps de fonction sur about:blank : {j}")
    j = call("executer_js", {"script": "throw new Error('boum')", "onglets": [{"fenetre_id": W, "index": 1}]})["resultats"][0]
    check(j["ok"] is False and "boum" in j.get("erreur", ""), f"exception JS : {j}")
    j = call("executer_js", {"script": "return (", "onglets": [{"fenetre_id": W, "index": 1}]})["resultats"][0]
    check(j["ok"] is False and "syntaxe" in j.get("erreur", ""), "erreur de syntaxe signalée")

    print("== Fermer des onglets")
    f = call("fermer", {"onglets": [{"fenetre_id": W, "index": 3, "url_attendue": "https://pas-celle-ci"}]})
    check(f["fermes"] == 0 and "différente" in f["onglets"][0].get("erreur", ""), "url_attendue protège l'onglet")
    f = call("fermer", {"onglets": [{"fenetre_id": W, "index": 3}, {"fenetre_id": W, "index": 4, "url_attendue": P2}]})
    check(f["fermes"] == 2, f"2 onglets fermés en lot (ordre décroissant) : {f}")
    check(len(call("onglets", {"fenetre_id": W})["onglets"]) == 2, "il reste 2 onglets")

    print("== Lectures de fichiers (filtrées sur le marqueur de test)")
    check(call("favoris", {"texte": "[mcp-test]"})["favoris"] == [], "favoris : aucun élément de test")
    check(call("favoris", {"texte": "[mcp-test]", "dossiers": True})["dossiers"] == [], "dossiers de favoris : aucun de test")
    rl = call("liste_de_lecture", {"texte": "mcp-test", "apercu": True})["elements"]
    check(all("mcp-test" in x["url"] or "mcp-test" in x["titre"] for x in rl), f"liste de lecture : {len(rl)} élément(s) de test seulement")
    check(call("groupes_onglets", {"texte": "[mcp-test]"})["groupes"] == [], "groupes d'onglets : aucun de test")
    hs = call("historique", {"texte": "mcp-test", "limite": 100})["pages"]
    check(all("mcp-test" in x["url"] + x["titre"] for x in hs), "historique filtré : seulement des pages de test")
    check(len(hs) == h_avant, f"fenêtre privée : aucune entrée d'historique ajoutée ({h_avant} → {len(hs)})")
    check(call("historique", {"texte": "mcp-test", "depuis": "2000-01-01", "jusqu_a": "2000-01-02"})["pages"] == [], "filtre de dates")
    check(call("historique", {"domaine": "mcp-test.invalid"})["pages"] == [], "filtre domaine")
    check("date invalide" in call("historique", {"depuis": "hier"}, expect_error=True), "date invalide refusée")

    print("== Fermer la fenêtre de test")
    f = call("fermer", {"fenetres": [W]})
    check(f["fenetres"][0]["ok"] is True, "fenêtre de test fermée")
    W_ferme = W
    time.sleep(0.5)
    check(W_ferme not in visibles(), "fenêtre de test disparue")
finally:
    print("== Nettoyage")
    if W is not None and W in visibles():
        subprocess.run(["osascript", "-e", f'tell application "Safari" to close window id {W}'])
        print(f"  fenêtre {W} fermée en nettoyage")
    check(visibles() == avant, "fenêtres visibles identiques à avant le test")
    proc.stdin.close()
    proc.wait(timeout=10)

total = time.time() - debut
lents = [(n, ms) for i, (n, ms, _) in enumerate(journal) if ms > 500]
print()
print(f"Durée totale : {total:.1f} s, {len(journal)} appels d'outils")
print("Appels > 0,5 s : " + (", ".join(f"{n} {ms} ms" for n, ms in lents) or "aucun"))
print("✓ TOUT PASSE" if not fails else f"✗ {len(fails)} échec(s) :\n  - " + "\n  - ".join(fails))
sys.exit(1 if fails else 0)
