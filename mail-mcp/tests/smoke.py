#!/usr/bin/env python3 -I
"""Test de bout en bout du serveur MCP Mail.

Lance le binaire, appelle chaque outil une fois (sauf envoyer : effet externe) sur des données de test marquées
(boîte locale MCP-TEST-<horodatage>, sujets [mcp-test], signature [mcp-test]), journalise durée et taille de
chaque appel, puis supprime tout par identifiant et vérifie qu'il ne reste rien.
Les lectures sont toujours filtrées sur la boîte de test ou sur le marqueur [mcp-test] <horodatage>.
Usage : python3 -I tests/smoke.py [chemin du binaire] [--nettoyage : seulement nettoyer les restes de tests]
"""
import glob
import json
import os
import shutil
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ARGS = [a for a in sys.argv[1:] if not a.startswith("--")]
SEUL_NETTOYAGE = "--nettoyage" in sys.argv
BIN = ARGS[0] if ARGS else os.path.join(ROOT, "bin/MailMCP")
TS = str(int(time.time()))
PREFIX = f"MCP-TEST-{TS}"
LOC = f"local/{PREFIX}"
SOUS = f"{LOC}/[mcp-test] sous"
RENOMMEE = f"{LOC}/[mcp-test] renommée"
SIG = f"[mcp-test] sig {TS}"
TMP = os.path.join(ROOT, "tests", f"tmp-{TS}")
PJ = os.path.join(TMP, "mcp-test.txt")
UI_SUPPR = os.path.join(ROOT, "tests", "supprimer_boite_test.applescript")
CONTENEUR = os.path.expanduser("~/Library/Containers/com.apple.mail/Data/tmp")

proc = subprocess.Popen([BIN], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
next_id = 0
fails = []
mesures = []  # (outil, ms, octets)


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
    ms = int((time.time() - t0) * 1000)
    text = res["content"][0]["text"]
    mesures.append((name, ms, len(text.encode())))
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


def osa(script, *args):
    r = subprocess.run(["osascript", "-e", script, *args], capture_output=True, text=True, timeout=60)
    return (r.stdout + r.stderr).strip()


def lire_boite(*boites, **kw):
    return call("messages", {"boites": list(boites), **kw})["messages"]


def sujets(ms):
    return sorted(m["sujet"] for m in ms)


T0 = time.time()
ids_test = set()
try:
    if SEUL_NETTOYAGE:
        rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "smoke", "version": "1"}})
        raise SystemExit
    os.makedirs(TMP, exist_ok=True)
    with open(PJ, "w") as f:
        f.write("contenu de test mcp\n")
    print(osa(f'tell application "Mail" to make new signature with properties {{name:"{SIG}", content:"Signature de test mcp"}}') or "  signature de test créée")

    print("== Protocole")
    init = rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "smoke", "version": "1"}})
    check(init["result"]["serverInfo"]["name"] == "mail", "initialize")
    rpc("notifications/initialized", notify=True)
    check(rpc("ping")["result"] == {}, "ping")
    tools = {t["name"]: t["annotations"] for t in rpc("tools/list")["result"]["tools"]}
    check(len(tools) == 12, f"tools/list : {len(tools)} outils")
    check([n for n, a in tools.items() if a["readOnlyHint"]] == ["boites", "messages", "lire_messages"], "readOnly : lectures seulement")
    check([n for n, a in tools.items() if a["destructiveHint"]] == ["supprimer_messages", "supprimer_boites"], "destructive : supprimer_messages et supprimer_boites")
    check([n for n, a in tools.items() if a["openWorldHint"]] == ["envoyer"], "openWorld : envoyer seulement")
    check(rpc("methode/inconnue").get("error", {}).get("code") == -32601, "méthode inconnue → -32601")
    check("outil inconnu" in call("outil_inexistant", expect_error=True), "outil inconnu → isError")

    print("== Boîtes")
    r = call("gerer_boites", {"creer": [{"chemin": PREFIX}, {"chemin": f"{PREFIX}/[mcp-test] sous"}]})["resultats"]
    check([x["id"] for x in r if x["ok"]] == [LOC, SOUS], f"boîtes créées : {r}")
    b = call("boites", {"nom_contient": PREFIX}) or {}
    check({x["id"] for x in b.get("boites", [])} == {LOC, SOUS}, f"boites filtrées : {b['boites']}")
    check(SIG in b.get("signatures", []) and any(c["id"] == "local" for c in b["comptes"]), "signature et compte local listés")

    print("== Brouillons")
    res = call("creer_brouillons", {"brouillons": [
        {"sujet": f"[mcp-test] complet {TS}", "corps": "Corps de test, mot-clé zéphyr.",
         "a": ["Dest Test <dest-test@example.com>"], "cc": ["copie-test@example.com"], "cci": ["cache-test@example.com"],
         "pieces_jointes": [PJ], "signature": SIG},
        {"sujet": f"[mcp-test] simple {TS}", "corps": "Corps simple.", "a": ["dest-test@example.com"]},
        {"sujet": f"[mcp-test] refusé {TS}", "pieces_jointes": [os.path.join(TMP, "absent.txt")]},
    ]})
    r0 = res["resultats"]
    check(res["crees"] == 2 and res["echecs"] == 1, f"2 créés, 1 refusé (pièce jointe absente) : {res['crees']}/{res['echecs']}")
    check(all("id" in x for x in r0[:2]), f"identifiants des brouillons : {[x.get('id') or x.get('avertissement') for x in r0[:2]]}")
    COMPLET, SIMPLE = r0[0].get("id"), r0[1].get("id")
    ids_test |= {COMPLET, SIMPLE}

    print("== Déplacer")
    res = call("deplacer_messages", {"ids": [COMPLET, SIMPLE], "boite": LOC})["resultats"]
    check(all(x["ok"] and "nouvel_id" in x for x in res), f"déplacés avec nouvel id : {res}")
    COMPLET, SIMPLE = (x.get("nouvel_id") for x in res)
    ids_test |= {COMPLET, SIMPLE}

    print("== Lister et chercher")
    ms = lire_boite(LOC)
    check(sujets(ms) == sorted([f"[mcp-test] complet {TS}", f"[mcp-test] simple {TS}"]), f"messages de la boîte : {sujets(ms)}")
    c = next((m for m in ms if m["id"] == COMPLET), {})
    check(c.get("pj") == 1 and c.get("boite") == LOC and "date" in c and "conv" in c, f"champs : {c}")
    check([m["id"] for m in lire_boite(LOC, texte="complet")] == [COMPLET], "filtre texte (sujet)")
    check([m["id"] for m in lire_boite(LOC, a="dest-test")] != [], "filtre destinataire")
    check([m["id"] for m in lire_boite(LOC, avec_pj=True)] == [COMPLET], "filtre avec_pj")
    check([m["id"] for m in lire_boite(LOC, dans_corps="zéphyr")] == [COMPLET], "recherche dans le corps")
    check(len(lire_boite(LOC, vue="aujourdhui")) == 2, "vue aujourdhui")
    page = call("messages", {"boites": [LOC], "limite": 1})
    check(page["total"] == 2 and len(page["messages"]) == 1 and page.get("tronque"), "limite + total")

    print("== Lire")
    lu = call("lire_messages", {"ids": [COMPLET, 999999999], "entetes": True})["messages"]
    m = lu[0]
    check("dest-test@example.com" in m.get("a", []) and m.get("cc") == ["copie-test@example.com"] and m.get("cci") == ["cache-test@example.com"], f"destinataires : {m.get('a')} {m.get('cc')} {m.get('cci')}")
    check("zéphyr" in m.get("corps", "") and "Signature de test mcp" in m.get("corps", ""), "corps + signature")
    check(m.get("pj") == [{"nom": "mcp-test.txt", "taille": 20, "type": "text/plain"}], f"pièce jointe : {m.get('pj')}")
    check("Mime-Version:" in m.get("entetes", ""), "en-têtes")
    check("erreur" in lu[1], "id inconnu signalé")

    print("== Marquer")
    res = call("marquer_messages", {"modifications": [
        {"id": COMPLET, "lu": False, "couleur_drapeau": "bleu", "couleur_fond": "vert"},
        {"id": SIMPLE, "lu": True, "drapeau": False, "indesirable": False},
        {"id": COMPLET, "couleur_drapeau": "fuchsia"},
    ]})
    check(sorted(res.get("modifies", [])) == sorted(x for x in [COMPLET, SIMPLE] if x) and len(res.get("echecs", [])) == 1, f"2 modifiés, 1 refusé : {res}")
    time.sleep(0.5)
    check([m["id"] for m in lire_boite(LOC, vue="non_lus")] == [COMPLET], "vue non_lus")
    check([m["id"] for m in lire_boite(LOC, vue="drapeau")] == [COMPLET], "vue drapeau")
    check([m["id"] for m in lire_boite(LOC, non_lu=False)] == [SIMPLE], "filtre non_lu false")

    print("== Réponse et transfert")
    res = call("creer_brouillons", {"brouillons": [
        {"repondre_a": COMPLET, "tous": True, "corps": "Réponse de test mcp."},
        {"transferer": COMPLET, "a": ["fwd-test@example.com"]},
    ]})
    r0 = res["resultats"]
    check(res["crees"] == 2 and all("id" in x for x in r0), f"réponse + transfert : {r0}")
    check(r0[0].get("sujet", "").startswith("Re:") and r0[1].get("sujet", "").startswith("Fwd:"), f"sujets : {[x.get('sujet') for x in r0]}")
    REP, FWD = r0[0].get("id"), r0[1].get("id")
    ids_test |= {REP, FWD}
    rl = {x["id"]: x for x in call("lire_messages", {"ids": [REP, FWD]})["messages"]}
    check(set(rl.get(REP, {}).get("cc", [])) == {"dest-test@example.com", "copie-test@example.com"}, f"répondre à tous : cc {rl.get(REP, {}).get('cc')}")
    check("Réponse de test mcp." in rl.get(REP, {}).get("corps", ""), "corps de la réponse")
    check(rl.get(FWD, {}).get("a") == ["fwd-test@example.com"] and len(rl.get(FWD, {}).get("pj", [])) == 1, f"transfert avec PJ : {rl.get(FWD, {}).get('a')} {rl.get(FWD, {}).get('pj')}")

    print("== Copier, ranger, supprimer")
    res = call("deplacer_messages", {"ids": [COMPLET], "boite": SOUS, "copier": True})["resultats"][0]
    check(res["ok"] and "nouvel_id" in res, f"copie : {res}")
    COPIE = res.get("nouvel_id")
    ids_test.add(COPIE)
    res = call("deplacer_messages", {"ids": [REP, FWD], "boite": SOUS})["resultats"]
    check(all("nouvel_id" in x for x in res), "brouillons rangés dans la boîte de test")
    REP, FWD = (x.get("nouvel_id") for x in res)
    ids_test |= {REP, FWD}
    check(len(lire_boite(LOC)) == 2, "la copie laisse l'original")
    conv = c.get("conv")
    check(COMPLET in [m["id"] for m in call("messages", {"boites": [LOC, SOUS], "conversation": conv})["messages"]], "filtre conversation")
    check(call("supprimer_messages", {"ids": [COPIE]})["supprimes"] == [COPIE], "copie supprimée (corbeille)")
    time.sleep(0.5)
    check(COPIE not in [m["id"] for m in lire_boite(SOUS)], "la copie a quitté la boîte")

    print("== Pièces jointes")
    res = call("enregistrer_pieces_jointes", {"ids": [COMPLET], "dossier": TMP + "/sortie"})["resultats"][0]
    f = (res.get("fichiers") or [""])[0]
    check(os.path.basename(f) == "mcp-test.txt" and open(f).read() == "contenu de test mcp\n", f"PJ enregistrée : {res}")

    print("== Vues et divers")
    check(lire_boite(LOC, vue="sans_reponse") == [], "vue sans_reponse (boîte de test : aucun envoyé)")
    call("messages", {"boites": [LOC], "vue": "selection"})
    check(True, "vue selection (filtrée sur la boîte de test)")
    check(len(lire_boite(LOC, SOUS, vue="recents")) == 4, "vue recents")
    r = call("gerer_boites", {"renommer": [{"id": SOUS, "nom": "[mcp-test] renommée"}]})["resultats"][0]
    check(r["ok"] and r["id"] == RENOMMEE, f"boîte renommée : {r}")
    check(call("relever")["ok"] is True, "relever")
except SystemExit:
    pass
finally:
    print("== Nettoyage")
    # Tout ce qui porte le marqueur, quel que soit le passage (corbeilles comprises), regroupé dans une boîte de test,
    # puis boîtes de test supprimées par le menu de Mail (AppleScript ne sait pas supprimer une boîte).
    def test_msgs():
        r = call("messages", {"texte": "[mcp-test]", "limite": 500})
        return [m for m in r.get("messages", []) if "[mcp-test]" in m["sujet"]] if isinstance(r, dict) else []

    def test_boites():
        r = call("boites", {"nom_contient": "MCP-TEST-"})
        return [b["id"] for b in r.get("boites", []) if b["id"].startswith("local/MCP-TEST-")] if isinstance(r, dict) else []

    # 3 passes : un brouillon iCloud déplacé juste après son enregistrement peut réapparaître dans Brouillons (synchro)
    for passe in range(3):
        try:
            msgs, boites = test_msgs(), test_boites()
            if not msgs and not boites:
                break
            dehors = [m["id"] for m in msgs if not m["boite"].startswith("local/MCP-TEST-")]
            if dehors:
                racine = next((b for b in boites if b.count("/") == 1), None)
                if racine is None:
                    racine = call("gerer_boites", {"creer": [{"chemin": f"{PREFIX}-nettoyage{passe}"}]})["resultats"][0]["id"]
                call("deplacer_messages", {"ids": dehors, "boite": racine})
                time.sleep(1)
            for b in sorted(test_boites(), key=lambda x: -x.count("/")):
                chemin = b[len("local/"):]
                if osa(f'tell application "Mail" to return exists mailbox "{chemin}"') == "true":
                    print("  ", osa(f'run script (POSIX file "{UI_SUPPR}") with parameters {{"{chemin}", "confirmer"}}'))
                    time.sleep(2)
        except Exception as e:  # noqa: BLE001
            print("  nettoyage :", e)
        time.sleep(5)
    osa('tell application "Mail" to delete (every signature whose name starts with "[mcp-test]")')
    for d in glob.glob(os.path.join(ROOT, "tests", "tmp-*")) + glob.glob(os.path.join(CONTENEUR, "mcp-mail-*")):
        shutil.rmtree(d, ignore_errors=True)
    time.sleep(2)
    restants = test_msgs()
    check(restants == [], f"0 message de test restant ({[(m['id'], m['boite']) for m in restants]})")
    check(test_boites() == [], "0 boîte de test restante")
    check(osa('tell application "Mail" to count (signatures whose name starts with "[mcp-test]")') == "0", "0 signature de test restante")
    check(not glob.glob(os.path.join(CONTENEUR, "mcp-mail-*")) and not glob.glob(os.path.join(ROOT, "tests", "tmp-*")), "0 fichier temporaire")
    proc.stdin.close()
    proc.wait(timeout=10)

total = time.time() - T0
print()
print(f"Durée totale : {total:.1f} s, {len(mesures)} appels")
lents = [(n, ms) for i, (n, ms, _) in enumerate(mesures) if ms > 500 and i > 0]
if not mesures:
    mesures.append(("aucun", 0, 0))
print("Appels > 0,5 s (hors 1er) : " + (", ".join(f"{n} {ms} ms" for n, ms in lents) or "aucun"))
print(f"Plus grosse réponse : {max(o for _, _, o in mesures)} o")
print("✓ TOUT PASSE" if not fails else f"✗ {len(fails)} échec(s) :\n  - " + "\n  - ".join(fails))
sys.exit(1 if fails else 0)
