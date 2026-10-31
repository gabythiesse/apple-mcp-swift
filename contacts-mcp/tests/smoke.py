#!/usr/bin/env python3 -I
"""Test de bout en bout du serveur MCP Contacts.

Lance le binaire, appelle chaque outil sur des données de test marquées (groupes MCP-TEST-<horodatage>,
contacts [mcp-test]), journalise la durée et la taille de chaque appel, puis supprime tout par identifiant
et vérifie qu'il ne reste rien. Les lectures sont toujours filtrées sur le groupe de test ou les identifiants de test.
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
BIN = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "bin/ContactsMCP")
TS = int(time.time())
PREFIX = f"MCP-TEST-{TS}"
TOK = f"mcptest{TS}"
N4 = f"{TS % 10000:04d}"
PNG = os.path.join(ROOT, "tests", f"pixel-{TS}.png")
VCF = os.path.join(ROOT, "tests", f"export-{TS}.vcf")

# Lancé dans une nouvelle session, comme un serveur démarré par l'app Claude (pas de terminal de contrôle)
proc = subprocess.Popen([BIN], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1, start_new_session=True)
next_id = 0
fails = []
calls = []  # (outil, ms, octets)


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
    calls.append((name, ms, len(text.encode())))
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


def lire(**kw):
    return call("contacts", kw)["contacts"]


def by_nom(items, prefix):
    return next((c for c in items if c["nom"].startswith(prefix)), {})


created_contacts, created_groups = [], []
t_start = time.time()
try:
    print("== Protocole")
    init = rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "smoke", "version": "1"}})
    check(init["result"]["serverInfo"]["name"] == "contacts", "initialize")
    rpc("notifications/initialized", notify=True)
    check(rpc("ping")["result"] == {}, "ping")
    tools = rpc("tools/list")["result"]["tools"]
    check(len(tools) == 13, f"tools/list : {len(tools)} outils")
    ro = sorted(t["name"] for t in tools if t["annotations"]["readOnlyHint"])
    de = sorted(t["name"] for t in tools if t["annotations"]["destructiveHint"])
    check(ro == ["contacts", "doublons", "groupes"] and de == ["fusionner_contacts", "supprimer_contacts", "supprimer_groupe"]
          and not any(t["annotations"]["openWorldHint"] for t in tools), "annotations")
    check(rpc("methode/inconnue").get("error", {}).get("code") == -32601, "méthode inconnue → -32601")
    check("outil inconnu" in call("outil_inexistant", expect_error=True), "outil inconnu → isError")

    print("== Groupes")
    gr = call("groupes", {"nom_contient": PREFIX})
    check(gr["groupes"] == [] and len(gr["comptes"]) >= 1 and any(c.get("par_defaut") for c in gr["comptes"]), "comptes listés, aucun groupe de test au départ")
    G = call("creer_groupe", {"nom": PREFIX})["id"]; created_groups.append(G)
    S = call("creer_groupe", {"nom": f"{PREFIX}-sous", "parent_id": G}); created_groups.insert(0, S["id"])
    check(S.get("parent_id") == G and "avertissement" not in S, "sous-groupe créé dans le parent")
    S = S["id"]
    call("modifier_groupe", {"id": G, "nom": f"{PREFIX}-A"})
    gs = {g["id"]: g for g in call("groupes", {"nom_contient": PREFIX})["groupes"]}
    check(gs.get(G, {}).get("nom") == f"{PREFIX}-A" and gs.get(S, {}).get("parent_id") == G, "groupe renommé, sous-groupe relié")
    check("impossible de sortir" in call("modifier_groupe", {"id": S, "parent_id": ""}, expect_error=True), "sortir un sous-groupe : refus explicite (limite Contacts)")
    check(call("groupes", {"nom_contient": f"{PREFIX}-sous"})["groupes"][0].get("parent_id") == G, "sous-groupe toujours dans le parent")

    print("== Création en lot")
    with open(PNG, "wb") as f:
        f.write(base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="))
    res = call("creer_contacts", {"contacts": [
        {"prenom": "[mcp-test] Alice", "nom_famille": TOK, "deuxieme_prenom": "M", "prefixe": "Dr", "surnom": "Ali",
         "nom_naissance": "Ancien", "societe": "[mcp-test] Org", "service": "R&D", "poste": "Testeuse",
         "telephones": [{"libelle": "travail", "valeur": f"01 99 00 {N4[:2]} {N4[2:]}"}, {"libelle": "ligne perso", "valeur": "+33 1 99 00 99 99"}],
         "emails": [{"libelle": "travail", "valeur": f"{TOK}@example.invalid"}],
         "adresses": [{"libelle": "domicile", "rue": "1 rue du Test", "ville": "Testville", "code_postal": "99999", "pays": "France", "code_pays": "FR"}],
         "urls": [{"libelle": "page_accueil", "valeur": "https://example.invalid"}],
         "anniversaire": (dt.date.today() + dt.timedelta(days=3)).strftime("--%m-%d"),
         "anniversaire_autre_calendrier": {"calendrier": "chinois", "mois": 1, "jour": 1},
         "dates": [{"libelle": "anniversaire", "date": "2020-06-15"}, {"libelle": "date perso", "date": "2021-01-02"}],
         "relations": [{"libelle": "soeur", "nom": "[mcp-test] Sœur"}, {"libelle": "parrain", "nom": "[mcp-test] Parrain"}],
         "reseaux": [{"service": "LinkedIn", "utilisateur": TOK}], "messageries": [{"service": "Skype", "utilisateur": TOK}],
         "photo": PNG, "note": f"note [mcp-test] {TOK}\nligne 2 « é »", "groupe_ids": [G]},
        {"prenom": "[mcp-test] Bob", "telephones": [f"06 39 98 {N4[:2]} {N4[2:]}"], "emails": [f"bob-{TOK}@example.invalid"],
         "note": "note de Bob", "groupe_ids": [G, S]},
        {"prenom": "[mcp-test] Alice", "nom_famille": TOK, "emails": [f"autre-{TOK}@example.invalid"],
         "telephones": [f"+33199 00{N4}"], "note": "note du doublon", "groupe_ids": [G]},
        {"societe": "[mcp-test] Société", "est_societe": True, "groupe_ids": [G]},
        {"poste": "sans nom"},
        {"prenom": "[mcp-test] date invalide", "anniversaire": "31/12"},
    ]})
    r0 = res["resultats"]
    check(res["crees"] == 4 and res["echecs"] == 2, f"4 créés, 2 refusés : {res['crees']}/{res['echecs']} {[r.get('erreur') for r in r0 if not r['ok']]}")
    check(all("avertissement" not in r for r in r0[:4]), "notes écrites sans avertissement : " + str([r.get("avertissement") for r in r0 if "avertissement" in r]))
    ALICE, BOB, ALICE2, SOC = (r.get("id") for r in r0[:4])
    created_contacts += [x for x in (ALICE, BOB, ALICE2, SOC) if x]
    os.remove(PNG)

    print("== Lecture")
    page = call("contacts", {"groupe_id": G})
    check(page["total"] == 4 and {c["id"] for c in page["contacts"]} == {ALICE, BOB, ALICE2, SOC}, f"4 membres du groupe : {page['total']}")
    soc = next((c for c in page["contacts"] if c["id"] == SOC), {})
    check(soc.get("est_societe") is True and soc.get("nom") == "[mcp-test] Société", f"fiche société : {soc}")
    a = call("contacts", {"ids": [ALICE], "detail": True})["contacts"][0]
    check(a.get("prenom") == "[mcp-test] Alice" and a.get("prefixe") == "Dr" and a.get("surnom") == "Ali" and a.get("nom_naissance") == "Ancien", "noms")
    check(a.get("societe") == "[mcp-test] Org" and a.get("service") == "R&D" and a.get("poste") == "Testeuse", "société, service, poste")
    check([t.get("libelle") for t in a.get("telephones", [])] == ["travail", "ligne perso"], f"téléphones + libellé perso : {a.get('telephones')}")
    check(a.get("emails") == [{"libelle": "travail", "valeur": f"{TOK}@example.invalid"}], f"email : {a.get('emails')}")
    ad = (a.get("adresses") or [{}])[0]
    check(ad.get("ville") == "Testville" and ad.get("libelle") == "domicile" and ad.get("code_pays") == "fr", f"adresse : {ad}")
    check(a.get("urls", [{}])[0].get("libelle") == "page_accueil", f"URL : {a.get('urls')}")
    check(a.get("anniversaire", "").startswith("--"), f"anniversaire sans année : {a.get('anniversaire')}")
    check(a.get("anniversaire_autre_calendrier", {}).get("calendrier") == "chinese", f"calendrier chinois : {a.get('anniversaire_autre_calendrier')}")
    check([d.get("libelle") for d in a.get("dates", [])] == ["anniversaire", "date perso"], f"dates : {a.get('dates')}")
    check(a.get("relations") == [{"libelle": "soeur", "valeur": "[mcp-test] Sœur"}, {"libelle": "parrain", "valeur": "[mcp-test] Parrain"}], f"relations : {a.get('relations')}")
    check(a.get("reseaux", [{}])[0].get("utilisateur") == TOK and a.get("messageries", [{}])[0].get("utilisateur") == TOK, "réseau, messagerie")
    check(a.get("photo") is True, "photo")
    check(a.get("note") == f"note [mcp-test] {TOK}\nligne 2 « é »", f"note : {a.get('note')!r}")
    check({g["id"] for g in a.get("groupes", [])} == {G}, f"groupes : {a.get('groupes')}")
    check("modifie_le" in a, "date de modification")
    check([c["id"] for c in lire(groupe_id=G, texte="TESTVILLE")] == [ALICE], "texte (ville, casse)")
    check([c["id"] for c in lire(groupe_id=G, texte="r&d")] == [ALICE], "texte (service)")
    check([c["id"] for c in lire(groupe_id=G, telephone=f"+33 6 39 98 {N4}")] == [BOB], "téléphone, autre format (+33 vs 06)")
    check([c["id"] for c in lire(groupe_id=G, email=f"BOB-{TOK}@example.invalid")] == [BOB], "email exact (casse)")
    check([c["id"] for c in lire(groupe_id=G, texte="NOTE DE BOB", dans_notes=True)] == [BOB], "recherche dans les notes")
    an = lire(groupe_id=G, anniversaires_jours=7)
    check([c["id"] for c in an] == [ALICE] and an[0].get("dans_jours") == 3, f"anniversaires à venir : {an}")
    check(len(lire(groupe_id=G, modifies_depuis=str(dt.date.today()))) == 4, "modifiés depuis aujourd'hui")
    check({c["id"] for c in lire(groupe_id=G, sans="email")} == {SOC}, "fiches sans email")
    check(lire(groupe_id=G, ma_carte=True) == [], "ma_carte filtrée sur le groupe de test (vide, sans erreur)")
    check(isinstance(lire(groupe_id=G, selection=True), list), "sélection de l'app filtrée sur le groupe de test (sans erreur)")
    p = call("contacts", {"groupe_id": G, "limite": 1})
    check(p["total"] == 4 and len(p["contacts"]) == 1 and "tronque" in p, "limite + total")
    check({c["id"] for c in lire(groupe_id=S)} == {BOB}, "membres du sous-groupe")

    print("== Modification en lot")
    res = call("modifier_contacts", {"modifications": [
        {"id": ALICE, "poste": "Cheffe", "retirer_emails": [f"{TOK}@example.invalid"], "ajouter_telephones": [{"libelle": "iphone", "valeur": "+33 1 99 00 88 88"}],
         "anniversaire": "1990-03-04", "photo": "", "note": "note modifiée", "surnom": ""},
        {"id": BOB, "adresses": [{"ville": "Bobville"}], "retirer_telephones": [f"0639 98{N4}"], "est_societe": False},
        {"id": "00000000-0000-0000-0000-000000000000:ABPerson", "poste": "x"},
    ]})
    check(res["modifies"] == 2 and res["echecs"] == 1, f"2 modifiés, 1 id inconnu refusé : {res['modifies']}/{res['echecs']}")
    det = {c["id"]: c for c in call("contacts", {"ids": [ALICE, BOB], "detail": True})["contacts"]}
    a, b = det.get(ALICE, {}), det.get(BOB, {})
    check(a.get("poste") == "Cheffe" and "emails" not in a and len(a.get("telephones", [])) == 3 and "surnom" not in a, "poste, email retiré, tél ajouté, surnom effacé")
    check(a.get("anniversaire") == "1990-03-04" and "photo" not in a and a.get("note") == "note modifiée", "anniversaire avec année, photo retirée, note")
    check(b.get("adresses") == [{"libelle": "domicile", "ville": "Bobville"}] and "telephones" not in b, f"adresse remplacée, tél retiré : {b.get('adresses')}")

    print("== Ranger")
    res = call("ranger_contacts", {"operations": [{"groupe_id": G, "retirer": [BOB]}, {"groupe_id": S, "ajouter": [ALICE]}]})
    check(res["faits"] == 2 and res["echecs"] == 0, f"retrait + ajout : {res}")
    check(BOB not in {c["id"] for c in lire(groupe_id=G)}, "Bob retiré du groupe")
    check({c["id"] for c in lire(groupe_id=S)} == {ALICE, BOB}, "Alice ajoutée au sous-groupe")

    print("== Doublons et fusion")
    d = call("doublons", {"groupe_id": G})["doublons"]
    check(len(d) == 1 and set(d[0]["ids"]) == {ALICE, ALICE2} and d[0]["raisons"] == ["nom", "telephone"], f"doublons : {d}")
    f = call("fusionner_contacts", {"cible_id": ALICE, "source_ids": [ALICE2]})
    check(f.get("sources_supprimees") == [ALICE2] and f.get("ajouts", {}).get("emails") == 1 and "telephones" not in f.get("ajouts", {}), f"fusion : {f.get('ajouts')}")
    created_contacts.remove(ALICE2)
    a = call("contacts", {"ids": [ALICE, ALICE2], "detail": True})["contacts"]
    check(len(a) == 1 and len(a[0].get("emails", [])) == 1 and len(a[0].get("telephones", [])) == 3, "source supprimée, email ajouté, tél en double ignoré")
    check(a[0].get("note") == "note modifiée\n\nnote du doublon", f"notes réunies : {a[0].get('note')!r}")

    print("== vCard")
    ex = call("exporter_vcard", {"ids": [ALICE, BOB], "chemin": VCF})
    txt = open(VCF, encoding="utf-8").read()
    check(ex.get("nb") == 2 and txt.count("BEGIN:VCARD") == 2 and "NOTE" in txt, f"export : {ex.get('nb')} fiches, note incluse")
    im = call("importer_vcard", {"chemin": VCF, "groupe_id": S})
    ids = [r.get("id") for r in im["resultats"] if r.get("ok")]
    created_contacts += ids
    check(im["crees"] == 2 and all("avertissement" not in r for r in im["resultats"]), f"import : {im['crees']} créés {[r.get('avertissement') for r in im['resultats']]}")
    rel = {c["nom"]: c for c in call("contacts", {"ids": ids, "detail": True})["contacts"]}
    check(any(c.get("note") == "note de Bob" for c in rel.values()) and len(rel) == 2, f"notes importées : {[c.get('note') for c in rel.values()]}")
    os.remove(VCF)

    print("== Suppressions")
    res = call("supprimer_contacts", {"ids": list(created_contacts) + ["00000000-0000-0000-0000-000000000000:ABPerson"]})
    check(res["supprimes"] == len(created_contacts) and res["echecs"] == 1, f"contacts supprimés : {res['supprimes']}/{len(created_contacts)}")
    created_contacts = [c for c in created_contacts if c not in {r.get("id") for r in res["resultats"] if r["ok"]}]
    res = call("supprimer_groupe", {"ids": list(created_groups)})
    check(all(r["ok"] for r in res["resultats"]), "groupes supprimés")
    created_groups = [g for g in created_groups if g not in {r.get("id") for r in res["resultats"] if r["ok"]}]
finally:
    print("== Nettoyage")
    for p in (PNG, VCF):
        if os.path.exists(p):
            os.remove(p)
    if created_contacts:
        call("supprimer_contacts", {"ids": created_contacts})
    if created_groups:
        call("supprimer_groupe", {"ids": created_groups})
    restant_g = call("groupes", {"nom_contient": PREFIX})["groupes"]
    check(restant_g == [], f"aucun groupe de test restant ({len(restant_g)})")
    proc.stdin.close()
    proc.wait(timeout=10)

total = time.time() - t_start
print()
print(f"Durée totale : {total:.1f} s, {len(calls)} appels")
lents = [(n, ms) for i, (n, ms, _) in enumerate(calls) if ms > 500]
print("Appels > 0,5 s :", lents if lents else "aucun")
print("✓ TOUT PASSE" if not fails else f"✗ {len(fails)} échec(s) :\n  - " + "\n  - ".join(fails))
sys.exit(1 if fails else 0)
