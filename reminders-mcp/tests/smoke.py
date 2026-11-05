#!/usr/bin/env python3 -I
"""End-to-end test of the Reminders MCP server.

Starts the binary, calls every tool once on tagged test data
(lists MCP-TEST-<timestamp>, reminders [mcp-test]), then deletes everything by ID
and checks nothing is left. Reads are always filtered to the test lists.
Usage: python3 -I tests/smoke.py [command and arguments]
  e.g. python3 -I tests/smoke.py ../bin/AppleMCP reminders   (through the launcher, which holds the Reminders permission)
"""
import base64
import datetime as dt
import json
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CMD = sys.argv[1:] or [os.path.join(ROOT, ".build/release/RemindersMCP")]
TS = int(time.time())
PREFIX = f"MCP-TEST-{TS}"
PNG = os.path.join(ROOT, "tests", "pixel.png")

proc = subprocess.Popen(CMD, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
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
        raise RuntimeError("the server stopped")
    return json.loads(line)


def call(name, args=None, expect_error=False):
    t0 = time.time()
    res = rpc("tools/call", {"name": name, "arguments": args or {}})["result"]
    text = res["content"][0]["text"]
    ms = int((time.time() - t0) * 1000)
    if res.get("isError"):
        if not expect_error:
            check(False, f"{name} failed: {text}")
        return text
    if expect_error:
        check(False, f"{name} should have failed: {text[:200]}")
    data = json.loads(text)
    print(f"   {name} ({ms} ms)")
    return data


def check(cond, label):
    print(("  ✓ " if cond else "  ✗ ") + label)
    if not cond:
        fails.append(label)


def by_title(items, title):
    return next((r for r in items if r["title"] == title), None)


def read(lists, **kw):
    return call("list_reminders", {"list_ids": lists, **kw})["reminders"]


today = dt.date.today()
tomorrow = today + dt.timedelta(days=1)
yesterday = today - dt.timedelta(days=1)
in3, in8, in10 = (today + dt.timedelta(days=n) for n in (3, 8, 10))
created_lists = []  # (id, is_group); cleaned up at the end no matter what

try:
    print("== Protocol")
    init = rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "smoke", "version": "1"}})
    check(init["result"]["serverInfo"]["name"] == "reminders", "initialize")
    rpc("notifications/initialized", notify=True)
    check(rpc("ping")["result"] == {}, "ping")
    tools = [t["name"] for t in rpc("tools/list")["result"]["tools"]]
    check(len(tools) == 14, f"tools/list: {len(tools)} tools")
    check(rpc("unknown/method").get("error", {}).get("code") == -32601, "unknown method → -32601")
    check("unknown tool" in call("no_such_tool", expect_error=True), "unknown tool → isError")

    print("== Lists and groups")
    A = call("create_list", {"name": f"{PREFIX}-A", "color": "green"})["id"]; created_lists.append((A, False))
    B = call("create_list", {"name": f"{PREFIX}-B"})["id"]; created_lists.append((B, False))
    G = call("create_list", {"name": f"{PREFIX}-GROUP", "group": True})["id"]; created_lists.append((G, True))
    C = call("create_list", {"name": f"{PREFIX}-C", "group_id": G}); created_lists.insert(0, (C["id"], False))
    check("warning" not in C, "list created inside a group")
    C = C["id"]
    ls = {l["id"]: l for l in call("list_lists", {"name_contains": PREFIX})["lists"]}
    check(len(ls) == 4, f"filtered lists: {len(ls)} of 4")
    check(ls.get(G, {}).get("group") is True, "group marked group: true")
    check(ls.get(C, {}).get("group_id") == G, "list C inside the group")
    check(ls.get(A, {}).get("color") == "#34C759", f"color of A: {ls.get(A, {}).get('color')}")
    call("update_list", {"id": A, "name": f"{PREFIX}-A2", "color": "#FF9500"})
    call("update_list", {"id": B, "group_id": G})
    check(call("list_lists", {"name_contains": f"{PREFIX}-B"})["lists"][0].get("group_id") == G, "B moved into the group")
    call("update_list", {"id": B, "group_id": ""})
    check("group_id" not in call("list_lists", {"name_contains": f"{PREFIX}-B"})["lists"][0], "B taken out of the group")
    call("update_list", {"id": G, "name": f"{PREFIX}-GROUP2"})
    ls = {l["id"]: l for l in call("list_lists", {"name_contains": PREFIX})["lists"]}
    check(ls[A]["name"] == f"{PREFIX}-A2" and ls[A].get("color") == "#FF9500", "A renamed and recolored")
    check(ls[G]["name"] == f"{PREFIX}-GROUP2" and ls[G].get("group") is True, "group renamed")

    print("== Sections")
    S1 = call("create_section", {"list_id": A, "name": "[mcp-test] S1"})["id"]
    S2 = call("create_section", {"list_id": A, "name": "[mcp-test] S2"})["id"]
    secs = call("list_sections", {"list_id": A})["sections"]
    check({s["id"] for s in secs} == {S1, S2}, f"sections of A: {len(secs)}")

    print("== Batch create")
    res = call("create_reminders", {"reminders": [
        {"title": "[mcp-test] full", "list_id": A, "notes": "test nöte", "due": f"{tomorrow}T09:30",
         "priority": "high", "flagged": True, "tags": ["mcptest", "#other"], "url": "https://example.com",
         "section_id": S1, "recurrence": {"frequency": "weekly", "days": ["monday", "thursday"], "occurrences": 3},
         "alarms": [{"date": f"{tomorrow}T09:00"}, {"minutes_before": 15},
                    {"location": "Eiffel Tower", "latitude": 48.8584, "longitude": 2.2945, "when": "departure"}],
         "subtasks": [{"title": "[mcp-test] st1"}, {"title": "[mcp-test] st2", "due": str(tomorrow)}]},
        {"title": "[mcp-test] simple", "list_id": A, "due": str(yesterday)},
        {"title": "[mcp-test] section2", "list_id": A, "section_id": S1},
        {"title": "", "list_id": A},
    ]})
    r0 = res["results"]
    check(res["created"] == 3 and res["failed"] == 1, f"3 created, 1 refused (empty title): {res['created']}/{res['failed']}")
    check(not any(r.get("warning", "").startswith("reminder created, but") for r in r0[:3]), "no ReminderKit warning: " + str([r["warning"] for r in r0[:3] if r.get("warning", "").startswith("reminder created, but")]))
    check(f"shows this reminder on {tomorrow}T09:00" in r0[0].get("warning", ""), f"dated alarms: warning names the date the app shows: {r0[0].get('warning')}")
    check(all("warning" not in r for r in r0[1:3]), "no warning without alarms")
    check(len(r0[0].get("subtasks", [])) == 2 and all(s["ok"] for s in r0[0]["subtasks"]), "2 subtasks created")
    FULL, SIMPLE, SEC2 = r0[0]["id"], r0[1]["id"], r0[2]["id"]
    ST1, ST2 = (s["id"] for s in r0[0]["subtasks"])

    print("== Read")
    rs = read([A], status="all")
    c = by_title(rs, "[mcp-test] full") or {}
    check(c.get("due") == f"{tomorrow}T09:30", f"due: {c.get('due')}")
    check(c.get("priority") == "high" and c.get("notes") == "test nöte", "priority, notes")
    check(c.get("flagged") is True and c.get("tags") == ["mcptest", "other"], f"flagged, tags: {c.get('tags')}")
    check(c.get("url") == "https://example.com", f"URL: {c.get('url')}")
    check(c.get("section_id") == S1, f"section: {c.get('section')}")
    check(c.get("recurrence", {}).get("days") == ["monday", "thursday"], f"recurrence: {c.get('recurrence')}")
    check(len(c.get("alarms", [])) == 3, f"alarms: {c.get('alarms')}")
    check(c.get("displayed_date") == f"{tomorrow}T09:00", f"displayed_date = earliest dated alarm, as in the app: {c.get('displayed_date')}")
    check("start" not in c, f"no start copied from due (EventKit does it, the app does not): {c.get('start')}")
    check(c.get("subtask_count") == 2, f"subtask_count: {c.get('subtask_count')}")
    check(by_title(rs, "[mcp-test] st1", ).get("parent_id") == FULL, "subtask linked to parent")
    check((by_title(rs, "[mcp-test] section2") or {}).get("section_id") == S1, "2nd reminder placed in S1")
    check(c.get("section_id") == S1, "1st reminder stays in S1 after the 2nd")
    check([r["title"] for r in read([A], view="overdue")] == ["[mcp-test] simple"], "view overdue")
    check("[mcp-test] simple" in [r["title"] for r in read([A], view="today")], "view today includes overdue")
    check("[mcp-test] full" in [r["title"] for r in read([A], view="week")], "view week")
    check(len(read([A], view="scheduled")) == 3, "view scheduled (3 with a due date)")
    check([r["title"] for r in read([A], view="flagged")] == ["[mcp-test] full"], "view flagged")
    check([r["title"] for r in read([A], text="TEST NOTE")] == ["[mcp-test] full"], "text search (case, accents)")
    check([r["title"] for r in read([A], tag="#mcptest")] == ["[mcp-test] full"], "tag filter")
    check({r["id"] for r in read([A], parent_id=FULL)} == {ST1, ST2}, "parent_id filter")
    check(len(read([A], due_after=str(today))) == 2, "due_after filter")
    check(len(read([A], due_before=str(today))) == 1, "due_before filter")
    check(len(read([A], no_due=True)) == 2, "no_due filter")
    page = call("list_reminders", {"list_ids": [A], "limit": 2})
    check(page["total"] == 5 and len(page["reminders"]) == 2 and "truncated" in page, "limit + total")
    tg = {t["tag"]: t["count"] for t in call("list_tags", {"list_ids": [A]})["tags"]}
    check(tg == {"mcptest": 1, "other": 1}, f"tags: {tg}")

    print("== Batch update")
    res = call("update_reminders", {"updates": [
        {"id": SIMPLE, "title": "[mcp-test] simple updated", "due": f"{tomorrow}T18:00", "flagged": True,
         "add_tags": ["x"], "url": "https://example.org", "section_id": S2, "priority": "low"},
        {"id": FULL, "remove_tags": ["other"], "url": "", "section_id": "", "flagged": False,
         "recurrence": None, "alarms": []},
        {"id": SEC2, "parent_id": FULL},
        {"id": ST1, "parent_id": ""},
        {"id": "00000000-0000-0000-0000-000000000000", "title": "x"},
    ]})
    check(res["updated"] == 4 and res["failed"] == 1, f"4 updated, 1 unknown id refused: {res['updated']}/{res['failed']} {[r.get('error') for r in res['results'] if not r['ok']]}")
    rs = read([A], status="all")
    s = by_title(rs, "[mcp-test] simple updated") or {}
    check(s.get("due") == f"{tomorrow}T18:00" and s.get("alarms") == [{"date": f"{tomorrow}T18:00"}], f"due + auto alert: {s.get('alarms')}")
    check("displayed_date" not in s and "start" not in s, f"alert at due time: the app shows due; start stays empty: {s.get('displayed_date')} {s.get('start')}")
    check(s.get("flagged") is True and s.get("tags") == ["x"] and s.get("url") == "https://example.org", "flag, tag, URL added")
    check(s.get("section_id") == S2 and s.get("priority") == "low", "section S2, priority low")
    c = by_title(rs, "[mcp-test] full") or {}
    check(c.get("tags") == ["mcptest"] and "url" not in c and "flagged" not in c, f"tag removed, URL removed, flag removed: {c.get('tags')}, {c.get('url')}")
    check("section_id" not in c, f"taken out of section: {c.get('section')}")
    check("recurrence" not in c and "alarms" not in c, f"recurrence and alarms removed: {c.get('recurrence')} {c.get('alarms')}")
    check("displayed_date" not in c, f"without alarms the app shows the due date again: {c.get('displayed_date')}")
    check((by_title(rs, "[mcp-test] section2") or {}).get("parent_id") == FULL, "reminder attached as subtask")
    st1 = by_title(rs, "[mcp-test] st1") or {}
    check("parent_id" not in st1 and st1.get("list_id") == A, "subtask detached, still in A")

    print("== Early reminder (the app's own setting, not an alarm)")
    res = call("create_reminders", {"reminders": [
        {"title": "[mcp-test] early", "list_id": C, "due": str(in10), "early_reminder": {"amount": 1, "unit": "weeks"}},
        {"title": "[mcp-test] early timed", "list_id": C, "due": f"{in10}T09:00", "early_reminder": {"amount": 30, "unit": "minutes"}},
        {"title": "[mcp-test] alarm before", "list_id": C, "due": str(in10), "alarms": [{"date": f"{in3}T18:00"}]},
        {"title": "[mcp-test] early without due", "list_id": C, "early_reminder": {"amount": 1, "unit": "days"}},
        {"title": "[mcp-test] early hours all-day", "list_id": C, "due": str(in10), "early_reminder": {"amount": 2, "unit": "hours"}},
    ]})
    r0 = res["results"]
    check(res["created"] == 3 and res["failed"] == 2, f"3 created, 2 refused (no due, hours on an all-day due): {res['created']}/{res['failed']} {[r.get('error') for r in r0 if not r['ok']]}")
    check("warning" not in r0[0] and "warning" not in r0[1], f"early reminder: no warning: {r0[0].get('warning')} {r0[1].get('warning')}")
    check(f"shows this reminder on {in3}T18:00" in r0[2].get("warning", ""), f"alarm before due: warning: {r0[2].get('warning')}")
    EARLY, EARLYT, ALARM = (r["id"] for r in r0[:3])
    rs = {r["id"]: r for r in read([C])}
    e = rs.get(EARLY, {})
    check(e.get("due") == str(in10) and e.get("early_reminder") == {"amount": 1, "unit": "weeks", "date": str(in3)}, f"early reminder 1 week: {e.get('early_reminder')}")
    check(bool(e) and not {"displayed_date", "alarms", "start"} & set(e), f"early reminder: the app shows the due date, no alarm, no start: {sorted(e)}")
    et = rs.get(EARLYT, {})
    check(et.get("early_reminder") == {"amount": 30, "unit": "minutes", "date": f"{in10}T08:30"}, f"early reminder 30 min: {et.get('early_reminder')}")
    check(et.get("alarms") == [{"date": f"{in10}T09:00"}] and "displayed_date" not in et, f"timed due: alert at due time, the app shows due: {et.get('alarms')}")
    al = rs.get(ALARM, {})
    check(al.get("due") == str(in10) and al.get("displayed_date") == f"{in3}T18:00", f"alarm before due: the app shows the alarm date: {al.get('displayed_date')}")
    res = call("update_reminders", {"updates": [
        {"id": EARLY, "early_reminder": {"amount": 2, "unit": "day"}},
        {"id": EARLYT, "early_reminder": None},
        {"id": ALARM, "alarms": [], "early_reminder": {"amount": 1, "unit": "weeks"}},
    ]})
    check(res["updated"] == 3 and all("warning" not in r for r in res["results"]), f"3 early reminders changed: {[r.get('error') or r.get('warning') for r in res['results'] if not r['ok'] or 'warning' in r]}")
    rs = {r["id"]: r for r in read([C])}
    check(rs.get(EARLY, {}).get("early_reminder") == {"amount": 2, "unit": "days", "date": str(in8)}, f"early reminder replaced: {rs.get(EARLY, {}).get('early_reminder')}")
    check("early_reminder" not in rs.get(EARLYT, {}) and rs.get(EARLYT, {}).get("due") == f"{in10}T09:00", "early reminder removed (null), due kept")
    al = rs.get(ALARM, {})
    check(al.get("early_reminder", {}).get("date") == str(in3) and not {"displayed_date", "alarms"} & set(al), f"alarm turned into an early reminder: the app shows due again: {sorted(al)}")
    call("update_reminders", {"updates": [{"id": EARLY, "due": ""}]})
    e = {r["id"]: r for r in read([C])}.get(EARLY, {})
    check(bool(e) and not {"due", "early_reminder", "start"} & set(e), f"due cleared: early reminder removed with it: {sorted(e)}")
    check("needs a due date" in call("update_reminders", {"updates": [{"id": EARLY, "early_reminder": {"amount": 1, "unit": "days"}}]})["results"][0].get("error", ""), "early reminder refused without due")

    print("== Moves")
    res = call("update_reminders", {"updates": [{"id": FULL, "list_id": B}, {"id": ST1, "list_id": B}]})
    check(res["updated"] == 2, f"moves: {[r.get('error') for r in res['results'] if not r['ok']]}")
    inB = {r["title"]: r for r in read([B], status="all")}
    check({"[mcp-test] full", "[mcp-test] st2", "[mcp-test] section2", "[mcp-test] st1"} <= set(inB), f"parent + subtasks + simple reminder in B: {sorted(inB)}")
    check(inB.get("[mcp-test] st2", {}).get("parent_id") == FULL, "subtasks keep their parent")
    res = call("update_reminders", {"updates": [{"id": ST2, "list_id": A}]})
    st2 = by_title(read([A], status="all"), "[mcp-test] st2") or {}
    check(res["updated"] == 1 and "parent_id" not in st2, "lone subtask moved (detached)")
    res = call("update_reminders", {"updates": [{"id": ST2, "parent_id": FULL}]})
    st2 = by_title(read([B], status="all"), "[mcp-test] st2") or {}
    check(res["updated"] == 1 and st2.get("parent_id") == FULL, "attached to a parent in another list")

    print("== Image")
    with open(PNG, "wb") as f:
        f.write(base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="))
    im = call("add_image", {"id": SIMPLE, "path": PNG})
    check(im.get("width") == 1, "image added")
    check((by_title(read([A]), "[mcp-test] simple updated") or {}).get("images") == 1, "image read back")
    os.remove(PNG)

    print("== Complete, reopen")
    call("complete_reminders", {"ids": [SIMPLE]})
    check("[mcp-test] simple updated" in [r["title"] for r in read([A], view="recently_completed")], "completed (view recently_completed)")
    call("complete_reminders", {"ids": [SIMPLE], "completed": False})
    check("[mcp-test] simple updated" in [r["title"] for r in read([A])], "reopened")

    print("== Deletions")
    call("delete_section", {"id": S2})
    check([s["id"] for s in call("list_sections", {"list_id": A})["sections"]] == [S1], "section deleted")
    check("section_id" not in (by_title(read([A]), "[mcp-test] simple updated") or {}), "its reminder stays in the list, outside any section")
    res = call("delete_reminders", {"ids": [FULL]})["results"][0]
    check(res["ok"] and res.get("deleted_subtasks") == 2, f"parent deleted with 2 subtasks: {res}")
    left = {r["title"] for r in read([B], status="all")}
    check(left == {"[mcp-test] st1"}, f"only st1 left in B: {sorted(left)}")
    check("contains" in call("delete_list", {"id": A}, expect_error=True), "non-empty list refused without force")
    check("contains" in call("delete_list", {"id": G}, expect_error=True), "non-empty group refused")
finally:
    print("== Cleanup")
    for lid, is_group in sorted(created_lists, key=lambda x: x[1]):  # lists first, then the group
        try:
            call("delete_list", {"id": lid, "force": True})
        except Exception as e:  # noqa: BLE001
            print("  cleanup", lid, e)
    remaining = call("list_lists", {"name_contains": PREFIX})["lists"]
    check(remaining == [], f"no test list left ({len(remaining)})")
    proc.stdin.close()
    proc.wait(timeout=10)

print()
print("✓ ALL PASS" if not fails else f"✗ {len(fails)} failure(s):\n  - " + "\n  - ".join(fails))
sys.exit(1 if fails else 0)
