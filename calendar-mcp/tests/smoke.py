#!/usr/bin/env python3 -I
"""Test de bout en bout du serveur MCP Calendrier.

Lance le binaire, appelle chaque outil une fois au moins sur des données de test marquées
(calendriers MCP-TEST-<horodatage>, événements [mcp-test]), puis supprime tout par identifiant
et vérifie qu'il ne reste rien. Les lectures sont toujours filtrées sur les calendriers de test.
inviter et repondre_invitations ne sont PAS appelés (effet externe : envoi aux participants).
Journalise la durée et la taille de chaque appel ; signale tout appel > 0,5 s hors premier appel.
Usage : python3 -I tests/smoke.py [chemin du binaire]
"""
import datetime as dt
import json
import os
import subprocess
import sys
import tempfile
import time
from zoneinfo import ZoneInfo

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BIN = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, ".build/release/CalendarMCP")
TS = int(time.time())
PREFIX = f"MCP-TEST-{TS}"

proc = subprocess.Popen([BIN], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
next_id = 0
fails = []
timings = []  # (outil, ms, octets)
T_START = time.time()


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
    timings.append((name, ms, len(text.encode())))
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


def lire(cals, **kw):
    args = {"calendrier_ids": cals, "debut": str(D - dt.timedelta(days=1)), "fin": str(D + dt.timedelta(days=400)), "limite": 500, **kw}
    return call("evenements", args)["evenements"]


def titres(evs, prefix):
    return [e for e in evs if e["titre"].startswith(prefix)]


today = dt.date.today()
D = today + dt.timedelta(days=2)
D5 = today + dt.timedelta(days=5)
WD = ["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"]
created = []  # identifiants de calendriers, supprimés à la fin quoi qu'il arrive
pj = os.path.join(tempfile.gettempdir(), f"mcp-test-{TS}.txt")

try:
    print("== Protocole")
    init = rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "smoke", "version": "1"}})
    check(init["result"]["serverInfo"]["name"] == "calendrier", "initialize")
    check(len(init["result"].get("instructions", "").splitlines()) <= 10, "instructions ≤ 10 lignes")
    rpc("notifications/initialized", notify=True)
    check(rpc("ping")["result"] == {}, "ping")
    tools = {t["name"]: t["annotations"] for t in rpc("tools/list")["result"]["tools"]}
    check(len(tools) == 11, f"tools/list : {len(tools)} outils")
    ro = {n for n, a in tools.items() if a["readOnlyHint"]}
    de = {n for n, a in tools.items() if a["destructiveHint"]}
    ow = {n for n, a in tools.items() if a["openWorldHint"]}
    check(ro == {"calendriers", "evenements", "creneaux_libres"}, f"readOnly : {sorted(ro)}")
    check(de == {"supprimer_calendrier", "supprimer_evenements"}, f"destructive : {sorted(de)}")
    check(ow == {"inviter", "repondre_invitations"}, f"openWorld : {sorted(ow)}")
    check(rpc("methode/inconnue").get("error", {}).get("code") == -32601, "méthode inconnue → -32601")
    check("outil inconnu" in call("outil_inexistant", expect_error=True), "outil inconnu → isError")

    print("== Calendriers")
    A = call("creer_calendrier", {"nom": f"{PREFIX}-A", "couleur": "vert"})["id"]; created.append(A)
    B = call("creer_calendrier", {"nom": f"{PREFIX}-B", "compte": "icloud"})["id"]; created.append(B)
    cs = call("calendriers", {"nom_contient": PREFIX})
    cals = {c["id"]: c for c in cs["calendriers"]}
    check(set(cals) == {A, B}, f"calendriers filtrés : {len(cals)} sur 2")
    check(cals[A].get("couleur") == "#34C759" and cals[A]["compte"] == "icloud", f"couleur et compte : {cals[A]}")
    check(any(c["type"] == "icloud" for c in cs["comptes"]), "comptes : iCloud listé")
    m = call("modifier_calendrier", {"id": A, "nom": f"{PREFIX}-A2", "couleur": "#FF9500"})
    check(m["nom"] == f"{PREFIX}-A2" and m.get("couleur") == "#FF9500", "calendrier renommé + recoloré")

    print("== Création en lot")
    with open(pj, "w") as f:
        f.write("pièce jointe de test")
    ny = dt.datetime(D.year, D.month, D.day, 9, 0, tzinfo=ZoneInfo("America/New_York")).astimezone().strftime("%Y-%m-%dT%H:%M")
    res = call("creer_evenements", {"evenements": [
        {"titre": "[mcp-test] complet", "calendrier_id": A, "debut": f"{D}T10:00", "fin": f"{D}T11:30",
         "lieu": "Tour Eiffel, Champ de Mars, Paris", "latitude": 48.8584, "longitude": 2.2945,
         "notes": "Rejoindre : https://zoom.us/j/1234567890", "url": "https://example.com", "disponibilite": "libre",
         "trajet_min": 30, "pieces_jointes": [pj],
         "alertes": [{"minutes_avant": 15}, {"date": f"{today}T18:00"},
                     {"lieu": "Maison test", "latitude": 48.85, "longitude": 2.35, "quand": "depart"}]},
        {"titre": "[mcp-test] journées", "calendrier_id": A, "debut": str(D + dt.timedelta(days=1)), "fin": str(D + dt.timedelta(days=3)),
         "alertes": [{"minutes_avant": 120}]},
        {"titre": "[mcp-test] journée sans alerte", "calendrier_id": A, "debut": str(D), "alertes": []},
        {"titre": "[mcp-test] 2e mardi", "calendrier_id": A, "debut": f"{D}T08:00", "duree_min": 30,
         "recurrence": {"frequence": "mois", "jours": ["2mardi"], "occurrences": 4}},
        {"titre": "[mcp-test] dernier jour ouvré", "calendrier_id": A, "debut": f"{D}T17:00",
         "recurrence": {"frequence": "mois", "jours": WD[:5], "positions": [-1], "occurrences": 3}},
        {"titre": "[mcp-test] lun-mer-ven", "calendrier_id": A, "debut": f"{D}T12:00",
         "recurrence": {"frequence": "semaine", "jours": ["lundi", "mercredi", "vendredi"], "fin_le": str(D + dt.timedelta(days=27))}},
        {"titre": "[mcp-test] New York", "calendrier_id": A, "debut": f"{D}T09:00", "fuseau": "America/New_York"},
        {"titre": "", "calendrier_id": A, "debut": str(D)},
    ]})
    r = res["resultats"]
    check(res["crees"] == 7 and res["echecs"] == 1, f"7 créés, 1 refusé (titre vide) : {res['crees']}/{res['echecs']}")
    check(all("avertissements" not in x for x in r[:7]), "aucun avertissement : " + str([x.get("avertissements") for x in r if "avertissements" in x]))
    COMPLET, JOURS, SANS, MARDI, OUVRE, LMV, NYC = (x.get("id") for x in r[:7])
    check(r[3].get("debut_recale") is True or D.weekday() == 1, "2e mardi : début recalé")
    check(r[6].get("debut") == ny, f"fuseau New York : {r[6].get('debut')} attendu {ny}")

    print("== Lecture")
    evs = lire([A], detail=True)
    c = next(e for e in evs if e["id"] == COMPLET)
    check(c.get("lieu") == "Tour Eiffel, Champ de Mars, Paris" and abs(c.get("latitude", 0) - 48.8584) < 1e-4, f"lieu texte + géoloc : {c.get('lieu')}")
    check(c.get("notes", "").startswith("Rejoindre") and c.get("url") == "https://example.com", "notes, URL")
    check(c.get("visio") == "https://zoom.us/j/1234567890", f"visio : {c.get('visio')}")
    check(c.get("disponibilite") == "libre" and c.get("trajet_min") == 30, f"disponibilité, trajet : {c.get('disponibilite')} {c.get('trajet_min')}")
    check(len(c.get("alertes", [])) == 3, f"3 alertes : {c.get('alertes')}")
    check(c.get("pieces_jointes") == [os.path.basename(pj)], f"pièce jointe : {c.get('pieces_jointes')}")
    j = next(e for e in evs if e["id"] == JOURS)
    check(j.get("jour") == str(D + dt.timedelta(days=1)) and j.get("jusqu_au") == str(D + dt.timedelta(days=3)), f"journées : {j.get('jour')} → {j.get('jusqu_au')}")
    check(j.get("alertes") == [{"minutes_avant": 120}], f"journée : seule l'alerte demandée (défaut iCloud retiré) : {j.get('alertes')}")
    s = next(e for e in evs if e["id"] == SANS)
    check("alertes" not in s, f"journée avec alertes [] : aucune alerte : {s.get('alertes')}")
    mardis = [e for e in evs if e["id"] == MARDI]
    jours_mardis = [dt.date.fromisoformat(e["debut"][:10]) for e in mardis]
    check(len(mardis) == 4 and all(x.weekday() == 1 and 8 <= x.day <= 14 for x in jours_mardis), f"2e mardi : 4 occurrences conformes {jours_mardis}")
    ouv = [dt.date.fromisoformat(e["debut"][:10]) for e in evs if e["id"] == OUVRE]
    def dernier_ouvre(x):
        nxt = (x.replace(day=28) + dt.timedelta(days=4)).replace(day=1)
        last = nxt - dt.timedelta(days=1)
        while last.weekday() > 4:
            last -= dt.timedelta(days=1)
        return last
    check(len(ouv) == 3 and all(x == dernier_ouvre(x) for x in ouv), f"dernier jour ouvré : {ouv}")
    lmv = sorted((e for e in evs if e["id"] == LMV), key=lambda e: e["debut"])
    check(len(lmv) >= 10 and all(dt.date.fromisoformat(e["debut"][:10]).weekday() in (0, 2, 4) for e in lmv), f"lun-mer-ven : {len(lmv)} occurrences conformes")
    check(all("occurrence" in e for e in lmv), "occurrences repérées par date")
    check(mardis[0].get("recurrence", {}).get("jours") == ["2mardi"], f"règle relue : {mardis[0].get('recurrence')}")
    one = call("evenements", {"id": LMV, "occurrence": lmv[1]["occurrence"]})["evenements"][0]
    check(one["occurrence"] == lmv[1]["occurrence"] and "recurrence" in one, "lecture d'une occurrence précise (détail)")
    found = call("evenements", {"calendrier_ids": [A], "texte": "ZOOM.US"})["evenements"]
    check([e["id"] for e in found] == [COMPLET], "recherche texte (casse) sur ±1 an")
    sem = call("evenements", {"calendrier_ids": [A], "vue": "semaine", "limite": 3})
    check(len(sem["evenements"]) == 3 and sem["total"] > 3 and "tronque" in sem, f"vue semaine + limite : {sem['total']}")
    check(call("evenements", {"calendrier_ids": [A], "vue": "aujourdhui"})["evenements"] == [], "vue aujourdhui (rien aujourd'hui dans A)")
    check(call("evenements", {"calendrier_ids": [A], "invitations": True})["evenements"] == [], "invitations en attente (aucune dans A)")

    print("== Créneaux libres et conflits")
    res = call("creer_evenements", {"evenements": [
        {"titre": "[mcp-test] libre", "calendrier_id": B, "debut": f"{D5}T10:00", "fin": f"{D5}T11:30", "disponibilite": "libre"},
        {"titre": "[mcp-test] occupé", "calendrier_id": B, "debut": f"{D5}T14:00", "fin": f"{D5}T15:00"},
        {"titre": "[mcp-test] chevauche", "calendrier_id": B, "debut": f"{D5}T14:30", "fin": f"{D5}T16:00"},
        {"titre": "[mcp-test] court", "calendrier_id": B, "debut": f"{D5}T16:10", "fin": f"{D5}T16:20"},
        {"titre": "[mcp-test] jour entier", "calendrier_id": B, "debut": str(D5)},
    ]})
    check(res["crees"] == 5, "5 événements pour les créneaux")
    cr = call("creneaux_libres", {"calendrier_ids": [B], "debut": str(D5), "fin": str(D5), "weekend": True})["creneaux"]
    got = [(x["debut"][11:], x["fin"][11:]) for x in cr]
    check(got == [("09:00", "14:00"), ("16:20", "18:00")], f"créneaux : {got}")
    cf = call("evenements", {"calendrier_ids": [B], "vue": "conflits", "debut": str(D5), "fin": str(D5)})["evenements"]
    check(sorted(e["titre"] for e in cf) == ["[mcp-test] chevauche", "[mcp-test] occupé"], f"conflits : {[e['titre'] for e in cf]}")

    print("== Modification en lot")
    o3, o6 = lmv[2], lmv[5]
    res = call("modifier_evenements", {"modifications": [
        {"id": LMV, "occurrence": o3["occurrence"], "titre": "[mcp-test] lun-mer-ven (déplacée)",
         "debut": o3["debut"][:11] + "14:00", "fin": o3["debut"][:11] + "15:00"},
        {"id": LMV, "occurrence": o6["occurrence"], "portee": "suivantes", "titre": "[mcp-test] lun-mer-ven (suite)"},
        {"id": MARDI, "occurrence": mardis[2]["occurrence"], "portee": "serie", "titre": "[mcp-test] 2e mardi (série)"},
        {"id": COMPLET, "calendrier_id": B, "alertes": [], "trajet_min": 0, "lieu": "Bureau", "url": "", "ajouter_pieces_jointes": ["/chemin/inexistant.txt"]},
        {"id": JOURS, "debut": str(D + dt.timedelta(days=10))},
        {"id": SANS, "titre": "[mcp-test] devenu horaire", "debut": f"{D}T07:00", "duree_min": 45},
        {"id": "inexistant", "titre": "x"},
    ]})
    rr = res["resultats"]
    check(res["modifies"] == 6 and res["echecs"] == 1, f"6 modifiés, 1 id inconnu refusé : {res['modifies']}/{res['echecs']} {[x.get('erreur') for x in rr if not x['ok']]}")
    check(rr[0]["id"] != LMV, "occurrence seule : nouvel id détaché")
    check(rr[3].get("avertissements") and "introuvable" in rr[3]["avertissements"][0], "pièce jointe inexistante : avertissement, pas de plantage")
    evA = lire([A], detail=True)
    evB = lire([B], detail=True)
    det = [e for e in evA if e["titre"] == "[mcp-test] lun-mer-ven (déplacée)"]
    check(len(det) == 1 and det[0]["debut"].endswith("14:00") and det[0].get("occurrence_modifiee"), "occurrence modifiée seule, déplacée à 14:00")
    avant = [e for e in evA if e["titre"] == "[mcp-test] lun-mer-ven"]
    suite = [e for e in evA if e["titre"] == "[mcp-test] lun-mer-ven (suite)"]
    check(len(avant) + len(suite) + 1 == len(lmv) and len(avant) == 4, f"suivantes : {len(avant)} avant + {len(suite)} suite + 1 = {len(lmv)}")
    check(len([e for e in evA if e["titre"] == "[mcp-test] 2e mardi (série)"]) == 4, "série entière renommée depuis une occurrence")
    cB = next((e for e in evB if e["id"] == COMPLET), {})
    check(cB.get("lieu") == "Bureau" and "latitude" not in cB and "alertes" not in cB and "trajet_min" not in cB and "url" not in cB,
          f"déplacé vers B, lieu remplacé, alertes/trajet/URL retirés : {cB}")
    jj = next(e for e in evA if e["id"] == JOURS)
    check(jj.get("jour") == str(D + dt.timedelta(days=10)) and jj.get("jusqu_au") == str(D + dt.timedelta(days=12)), f"journées décalées, durée gardée : {jj.get('jour')} → {jj.get('jusqu_au')}")
    h = next(e for e in evA if e["id"] == SANS)
    check(h.get("debut") == f"{D}T07:00" and h.get("fin") == f"{D}T07:45", f"journée → horaire : {h.get('debut')} {h.get('fin')}")

    print("== Suppressions")
    suite_sorted = sorted(suite, key=lambda e: e["debut"])
    res = call("supprimer_evenements", {"evenements": [
        {"id": suite_sorted[0]["id"], "occurrence": suite_sorted[0]["occurrence"]},
        OUVRE,
        NYC,
    ]})
    check(res["supprimes"] == 3, f"3 suppressions : {[x.get('erreur') for x in res['resultats'] if not x['ok']]}")
    evA = lire([A])
    check(len([e for e in evA if e["titre"] == "[mcp-test] lun-mer-ven (suite)"]) == len(suite) - 1, "une seule occurrence supprimée")
    check(not any(e["id"] in (OUVRE, NYC) for e in evA), "série entière et événement simple supprimés")
    check("contient" in call("supprimer_calendrier", {"id": A}, expect_error=True), "calendrier non vide refusé sans force")
finally:
    print("== Nettoyage")
    for cid in created:
        try:
            call("supprimer_calendrier", {"id": cid, "force": True})
        except Exception as e:  # noqa: BLE001
            print("  nettoyage", cid, e)
    if os.path.exists(pj):
        os.remove(pj)
    restant = call("calendriers", {"nom_contient": "MCP-TEST-"})["calendriers"]
    check(restant == [], f"aucun calendrier MCP-TEST restant ({len(restant)})")
    proc.stdin.close()
    proc.wait(timeout=10)

total = time.time() - T_START
slow = [(n, ms) for i, (n, ms, _) in enumerate(timings) if ms > 500 and i > 0]
print()
print(f"Durée totale : {total:.1f} s, {len(timings)} appels d'outil, 1er appel {timings[0][1]} ms, max {max(t[1] for t in timings)} ms, "
      f"réponse max {max(t[2] for t in timings)} o")
print("Appels > 0,5 s (hors 1er) : " + (", ".join(f"{n} {ms} ms" for n, ms in slow) if slow else "aucun"))
print("✓ TOUT PASSE" if not fails else f"✗ {len(fails)} échec(s) :\n  - " + "\n  - ".join(fails))
sys.exit(1 if fails else 0)
