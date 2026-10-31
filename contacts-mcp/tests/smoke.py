#!/usr/bin/env python3 -I
"""End-to-end test of the Contacts MCP server.

Starts the binary, calls every tool on marked test data (groups MCP-TEST-<timestamp>,
contacts [mcp-test]), logs the duration and size of each call, then deletes everything by identifier
and checks that nothing is left. Reads are always filtered on the test group or the test identifiers.
Usage: python3 -I tests/smoke.py [path to the binary]
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

# Started in a new session, like a server launched by the Claude app (no controlling terminal)
proc = subprocess.Popen([BIN], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1, start_new_session=True)
next_id = 0
fails = []
calls = []  # (tool, ms, bytes)


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
        raise RuntimeError("the server stopped")
    return json.loads(line)


def call(name, args=None, expect_error=False):
    t0 = time.time()
    res = rpc("tools/call", {"name": name, "arguments": args or {}})["result"]
    text = res["content"][0]["text"]
    ms = int((time.time() - t0) * 1000)
    calls.append((name, ms, len(text.encode())))
    print(f"   {name} ({ms} ms, {len(text.encode())} B)")
    if res.get("isError"):
        if not expect_error:
            check(False, f"{name} failed: {text}")
        return text
    if expect_error:
        check(False, f"{name} should have failed: {text[:200]}")
    return json.loads(text)


def check(cond, label):
    print(("  ✓ " if cond else "  ✗ ") + label)
    if not cond:
        fails.append(label)


def read(**kw):
    return call("list_contacts", kw)["contacts"]


created_contacts, created_groups = [], []
t_start = time.time()
try:
    print("== Protocol")
    init = rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "smoke", "version": "1"}})
    check(init["result"]["serverInfo"]["name"] == "contacts", "initialize")
    rpc("notifications/initialized", notify=True)
    check(rpc("ping")["result"] == {}, "ping")
    tools = rpc("tools/list")["result"]["tools"]
    check(len(tools) == 13, f"tools/list: {len(tools)} tools")
    ro = sorted(t["name"] for t in tools if t["annotations"]["readOnlyHint"])
    de = sorted(t["name"] for t in tools if t["annotations"]["destructiveHint"])
    check(ro == ["find_duplicates", "list_contacts", "list_groups"] and de == ["delete_contacts", "delete_group", "merge_contacts"]
          and not any(t["annotations"]["openWorldHint"] for t in tools), "annotations")
    check(rpc("unknown/method").get("error", {}).get("code") == -32601, "unknown method → -32601")
    check("unknown tool" in call("no_such_tool", expect_error=True), "unknown tool → isError")

    print("== Groups")
    gr = call("list_groups", {"name_contains": PREFIX})
    check(gr["groups"] == [] and len(gr["accounts"]) >= 1 and any(c.get("default") for c in gr["accounts"]), "accounts listed, no test group at start")
    G = call("create_group", {"name": PREFIX})["id"]; created_groups.append(G)
    S = call("create_group", {"name": f"{PREFIX}-sub", "parent_id": G}); created_groups.insert(0, S["id"])
    check(S.get("parent_id") == G and "warning" not in S, "subgroup created in the parent")
    S = S["id"]
    call("update_group", {"id": G, "name": f"{PREFIX}-A"})
    gs = {g["id"]: g for g in call("list_groups", {"name_contains": PREFIX})["groups"]}
    check(gs.get(G, {}).get("name") == f"{PREFIX}-A" and gs.get(S, {}).get("parent_id") == G, "group renamed, subgroup linked")
    check("cannot take a subgroup out" in call("update_group", {"id": S, "parent_id": ""}, expect_error=True), "taking a subgroup out: explicit refusal (Contacts limitation)")
    check(call("list_groups", {"name_contains": f"{PREFIX}-sub"})["groups"][0].get("parent_id") == G, "subgroup still in the parent")

    print("== Batch create")
    with open(PNG, "wb") as f:
        f.write(base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="))
    res = call("create_contacts", {"contacts": [
        {"first_name": "[mcp-test] Alice", "last_name": TOK, "middle_name": "M", "prefix": "Dr", "nickname": "Ali",
         "maiden_name": "Former", "organization": "[mcp-test] Org", "department": "R&D", "job_title": "Tester",
         "phones": [{"label": "work", "value": f"01 99 00 {N4[:2]} {N4[2:]}"}, {"label": "personal line", "value": "+33 1 99 00 99 99"}],
         "emails": [{"label": "work", "value": f"{TOK}@example.invalid"}],
         "addresses": [{"label": "home", "street": "1 Test Street", "city": "Testville", "postal_code": "99999", "country": "France", "country_code": "FR"}],
         "urls": [{"label": "homepage", "value": "https://example.invalid"}],
         "birthday": (dt.date.today() + dt.timedelta(days=3)).strftime("--%m-%d"),
         "alternate_birthday": {"calendar": "chinese", "month": 1, "day": 1},
         "dates": [{"label": "anniversary", "date": "2020-06-15"}, {"label": "personal date", "date": "2021-01-02"}],
         "related_names": [{"label": "sister", "name": "[mcp-test] Zoë"}, {"label": "godfather", "name": "[mcp-test] Godfather"}],
         "social_profiles": [{"service": "LinkedIn", "username": TOK}], "instant_messages": [{"service": "Skype", "username": TOK}],
         "photo": PNG, "note": f"note [mcp-test] {TOK}\nline 2 « é »", "group_ids": [G]},
        {"first_name": "[mcp-test] Bob", "phones": [f"06 39 98 {N4[:2]} {N4[2:]}"], "emails": [f"bob-{TOK}@example.invalid"],
         "note": "Bob's note", "group_ids": [G, S]},
        {"first_name": "[mcp-test] Alice", "last_name": TOK, "emails": [f"other-{TOK}@example.invalid"],
         "phones": [f"+33199 00{N4}"], "note": "duplicate's note", "group_ids": [G]},
        {"organization": "[mcp-test] Company", "is_company": True, "group_ids": [G]},
        {"job_title": "no name"},
        {"first_name": "[mcp-test] invalid date", "birthday": "31/12"},
    ]})
    r0 = res["results"]
    check(res["created"] == 4 and res["failed"] == 2, f"4 created, 2 rejected: {res['created']}/{res['failed']} {[r.get('error') for r in r0 if not r['ok']]}")
    check(all("warning" not in r for r in r0[:4]), "notes written without warning: " + str([r.get("warning") for r in r0 if "warning" in r]))
    ALICE, BOB, ALICE2, SOC = (r.get("id") for r in r0[:4])
    created_contacts += [x for x in (ALICE, BOB, ALICE2, SOC) if x]
    os.remove(PNG)

    print("== Read")
    page = call("list_contacts", {"group_id": G})
    check(page["total"] == 4 and {c["id"] for c in page["contacts"]} == {ALICE, BOB, ALICE2, SOC}, f"4 group members: {page['total']}")
    soc = next((c for c in page["contacts"] if c["id"] == SOC), {})
    check(soc.get("is_company") is True and soc.get("name") == "[mcp-test] Company", f"company card: {soc}")
    a = call("list_contacts", {"ids": [ALICE], "detail": True})["contacts"][0]
    check(a.get("first_name") == "[mcp-test] Alice" and a.get("prefix") == "Dr" and a.get("nickname") == "Ali" and a.get("maiden_name") == "Former", "names")
    check(a.get("organization") == "[mcp-test] Org" and a.get("department") == "R&D" and a.get("job_title") == "Tester", "organization, department, job title")
    check([t.get("label") for t in a.get("phones", [])] == ["work", "personal line"], f"phones + custom label: {a.get('phones')}")
    check(a.get("emails") == [{"label": "work", "value": f"{TOK}@example.invalid"}], f"email: {a.get('emails')}")
    ad = (a.get("addresses") or [{}])[0]
    check(ad.get("city") == "Testville" and ad.get("label") == "home" and ad.get("country_code") == "fr", f"address: {ad}")
    check(a.get("urls", [{}])[0].get("label") == "homepage", f"URL: {a.get('urls')}")
    check(a.get("birthday", "").startswith("--"), f"birthday without a year: {a.get('birthday')}")
    check(a.get("alternate_birthday", {}).get("calendar") == "chinese", f"Chinese calendar: {a.get('alternate_birthday')}")
    check([d.get("label") for d in a.get("dates", [])] == ["anniversary", "personal date"], f"dates: {a.get('dates')}")
    check(a.get("related_names") == [{"label": "sister", "value": "[mcp-test] Zoë"}, {"label": "godfather", "value": "[mcp-test] Godfather"}], f"related names: {a.get('related_names')}")
    check(a.get("social_profiles", [{}])[0].get("username") == TOK and a.get("instant_messages", [{}])[0].get("username") == TOK, "social profile, instant message")
    check(a.get("photo") is True, "photo")
    check(a.get("note") == f"note [mcp-test] {TOK}\nline 2 « é »", f"note: {a.get('note')!r}")
    check({g["id"] for g in a.get("groups", [])} == {G}, f"groups: {a.get('groups')}")
    check("modified_at" in a, "modification date")
    check([c["id"] for c in read(group_id=G, text="TESTVILLE")] == [ALICE], "text (city, case)")
    check([c["id"] for c in read(group_id=G, text="r&d")] == [ALICE], "text (department)")
    check([c["id"] for c in read(group_id=G, phone=f"+33 6 39 98 {N4}")] == [BOB], "phone, other format (+33 vs 06)")
    check([c["id"] for c in read(group_id=G, email=f"BOB-{TOK}@example.invalid")] == [BOB], "exact email (case)")
    check([c["id"] for c in read(group_id=G, text="BOB'S NOTE", in_notes=True)] == [BOB], "search in notes")
    an = read(group_id=G, birthdays_within_days=7)
    check([c["id"] for c in an] == [ALICE] and an[0].get("days_until") == 3, f"upcoming birthdays: {an}")
    check(len(read(group_id=G, modified_since=str(dt.date.today()))) == 4, "modified since today")
    check({c["id"] for c in read(group_id=G, missing="email")} == {SOC}, "cards without an email")
    check(read(group_id=G, my_card=True) == [], "my_card filtered on the test group (empty, no error)")
    check(isinstance(read(group_id=G, selection=True), list), "app selection filtered on the test group (no error)")
    p = call("list_contacts", {"group_id": G, "limit": 1})
    check(p["total"] == 4 and len(p["contacts"]) == 1 and "truncated" in p, "limit + total")
    check({c["id"] for c in read(group_id=S)} == {BOB}, "subgroup members")

    print("== Batch update")
    res = call("update_contacts", {"updates": [
        {"id": ALICE, "job_title": "Lead", "remove_emails": [f"{TOK}@example.invalid"], "add_phones": [{"label": "iphone", "value": "+33 1 99 00 88 88"}],
         "birthday": "1990-03-04", "photo": "", "note": "updated note", "nickname": ""},
        {"id": BOB, "addresses": [{"city": "Bobville"}], "remove_phones": [f"0639 98{N4}"], "is_company": False},
        {"id": "00000000-0000-0000-0000-000000000000:ABPerson", "job_title": "x"},
    ]})
    check(res["updated"] == 2 and res["failed"] == 1, f"2 updated, 1 unknown id rejected: {res['updated']}/{res['failed']}")
    det = {c["id"]: c for c in call("list_contacts", {"ids": [ALICE, BOB], "detail": True})["contacts"]}
    a, b = det.get(ALICE, {}), det.get(BOB, {})
    check(a.get("job_title") == "Lead" and "emails" not in a and len(a.get("phones", [])) == 3 and "nickname" not in a, "job title, email removed, phone added, nickname cleared")
    check(a.get("birthday") == "1990-03-04" and "photo" not in a and a.get("note") == "updated note", "birthday with year, photo removed, note")
    check(b.get("addresses") == [{"label": "home", "city": "Bobville"}] and "phones" not in b, f"address replaced, phone removed: {b.get('addresses')}")

    print("== Organize")
    res = call("organize_contacts", {"operations": [{"group_id": G, "remove": [BOB]}, {"group_id": S, "add": [ALICE]}]})
    check(res["done"] == 2 and res["failed"] == 0, f"remove + add: {res}")
    check(BOB not in {c["id"] for c in read(group_id=G)}, "Bob removed from the group")
    check({c["id"] for c in read(group_id=S)} == {ALICE, BOB}, "Alice added to the subgroup")

    print("== Duplicates and merge")
    d = call("find_duplicates", {"group_id": G})["duplicates"]
    check(len(d) == 1 and set(d[0]["ids"]) == {ALICE, ALICE2} and d[0]["reasons"] == ["name", "phone"], f"duplicates: {d}")
    f = call("merge_contacts", {"target_id": ALICE, "source_ids": [ALICE2]})
    check(f.get("deleted_source_ids") == [ALICE2] and f.get("added", {}).get("emails") == 1 and "phones" not in f.get("added", {}), f"merge: {f.get('added')}")
    created_contacts.remove(ALICE2)
    a = call("list_contacts", {"ids": [ALICE, ALICE2], "detail": True})["contacts"]
    check(len(a) == 1 and len(a[0].get("emails", [])) == 1 and len(a[0].get("phones", [])) == 3, "source deleted, email added, duplicate phone ignored")
    check(a[0].get("note") == "updated note\n\nduplicate's note", f"notes combined: {a[0].get('note')!r}")

    print("== vCard")
    ex = call("export_vcard", {"ids": [ALICE, BOB], "path": VCF})
    txt = open(VCF, encoding="utf-8").read()
    check(ex.get("count") == 2 and txt.count("BEGIN:VCARD") == 2 and "NOTE" in txt, f"export: {ex.get('count')} cards, note included")
    im = call("import_vcard", {"path": VCF, "group_id": S})
    ids = [r.get("id") for r in im["results"] if r.get("ok")]
    created_contacts += ids
    check(im["created"] == 2 and all("warning" not in r for r in im["results"]), f"import: {im['created']} created {[r.get('warning') for r in im['results']]}")
    rel = {c["name"]: c for c in call("list_contacts", {"ids": ids, "detail": True})["contacts"]}
    check(any(c.get("note") == "Bob's note" for c in rel.values()) and len(rel) == 2, f"imported notes: {[c.get('note') for c in rel.values()]}")
    os.remove(VCF)

    print("== Deletions")
    res = call("delete_contacts", {"ids": list(created_contacts) + ["00000000-0000-0000-0000-000000000000:ABPerson"]})
    check(res["deleted"] == len(created_contacts) and res["failed"] == 1, f"contacts deleted: {res['deleted']}/{len(created_contacts)}")
    created_contacts = [c for c in created_contacts if c not in {r.get("id") for r in res["results"] if r["ok"]}]
    res = call("delete_group", {"ids": list(created_groups)})
    check(all(r["ok"] for r in res["results"]), "groups deleted")
    created_groups = [g for g in created_groups if g not in {r.get("id") for r in res["results"] if r["ok"]}]
finally:
    print("== Cleanup")
    for p in (PNG, VCF):
        if os.path.exists(p):
            os.remove(p)
    if created_contacts:
        call("delete_contacts", {"ids": created_contacts})
    if created_groups:
        call("delete_group", {"ids": created_groups})
    left_g = call("list_groups", {"name_contains": PREFIX})["groups"]
    check(left_g == [], f"no test group left ({len(left_g)})")
    proc.stdin.close()
    proc.wait(timeout=10)

total = time.time() - t_start
print()
print(f"Total duration: {total:.1f} s, {len(calls)} calls")
slow = [(n, ms) for i, (n, ms, _) in enumerate(calls) if ms > 500]
print("Calls > 0.5 s:", slow if slow else "none")
print("✓ ALL PASS" if not fails else f"✗ {len(fails)} failure(s):\n  - " + "\n  - ".join(fails))
sys.exit(1 if fails else 0)
