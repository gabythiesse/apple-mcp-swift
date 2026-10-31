#!/usr/bin/env python3 -I
"""End-to-end test of the Calendar MCP server.

Starts the binary, calls every tool at least once on marked test data
(calendars MCP-TEST-<timestamp>, events [mcp-test]), then deletes everything by identifier
and checks nothing is left. Reads are always filtered on the test calendars.
invite and respond_to_invitations are NOT called (external effect: messages to attendees).
Logs the duration and size of each call; flags any call > 0.5 s except the first one.
Usage: python3 -I tests/smoke.py [binary path]
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
timings = []  # (tool, ms, bytes)
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
        raise RuntimeError("the server stopped")
    return json.loads(line)


def call(name, args=None, expect_error=False):
    t0 = time.time()
    res = rpc("tools/call", {"name": name, "arguments": args or {}})["result"]
    text = res["content"][0]["text"]
    ms = int((time.time() - t0) * 1000)
    timings.append((name, ms, len(text.encode())))
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


def read(cals, **kw):
    args = {"calendar_ids": cals, "start": str(D - dt.timedelta(days=1)), "end": str(D + dt.timedelta(days=400)), "limit": 500, **kw}
    return call("list_events", args)["events"]


def titles(evs, prefix):
    return [e for e in evs if e["title"].startswith(prefix)]


today = dt.date.today()
D = today + dt.timedelta(days=2)
D5 = today + dt.timedelta(days=5)
WD = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
created = []  # calendar identifiers, deleted at the end no matter what
pj = os.path.join(tempfile.gettempdir(), f"mcp-test-{TS}.txt")

try:
    print("== Protocol")
    init = rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "smoke", "version": "1"}})
    check(init["result"]["serverInfo"]["name"] == "calendar", "initialize")
    check(len(init["result"].get("instructions", "").splitlines()) <= 10, "instructions ≤ 10 lines")
    rpc("notifications/initialized", notify=True)
    check(rpc("ping")["result"] == {}, "ping")
    tools = {t["name"]: t["annotations"] for t in rpc("tools/list")["result"]["tools"]}
    check(len(tools) == 11, f"tools/list: {len(tools)} tools")
    ro = {n for n, a in tools.items() if a["readOnlyHint"]}
    de = {n for n, a in tools.items() if a["destructiveHint"]}
    ow = {n for n, a in tools.items() if a["openWorldHint"]}
    check(ro == {"list_calendars", "list_events", "find_free_slots"}, f"readOnly: {sorted(ro)}")
    check(de == {"delete_calendar", "delete_events"}, f"destructive: {sorted(de)}")
    check(ow == {"invite", "respond_to_invitations"}, f"openWorld: {sorted(ow)}")
    check(rpc("unknown/method").get("error", {}).get("code") == -32601, "unknown method → -32601")
    check("unknown tool" in call("nonexistent_tool", expect_error=True), "unknown tool → isError")

    print("== Calendars")
    A = call("create_calendar", {"name": f"{PREFIX}-A", "color": "green"})["id"]; created.append(A)
    B = call("create_calendar", {"name": f"{PREFIX}-B", "account": "icloud"})["id"]; created.append(B)
    cs = call("list_calendars", {"name_contains": PREFIX})
    cals = {c["id"]: c for c in cs["calendars"]}
    check(set(cals) == {A, B}, f"filtered calendars: {len(cals)} of 2")
    check(cals[A].get("color") == "#34C759" and cals[A]["account"] == "icloud", f"color and account: {cals[A]}")
    check(any(c["type"] == "icloud" for c in cs["accounts"]), "accounts: iCloud listed")
    m = call("update_calendar", {"id": A, "name": f"{PREFIX}-A2", "color": "#FF9500"})
    check(m["name"] == f"{PREFIX}-A2" and m.get("color") == "#FF9500", "calendar renamed + recolored")

    print("== Batch create")
    with open(pj, "w") as f:
        f.write("test attachment")
    ny = dt.datetime(D.year, D.month, D.day, 9, 0, tzinfo=ZoneInfo("America/New_York")).astimezone().strftime("%Y-%m-%dT%H:%M")
    res = call("create_events", {"events": [
        {"title": "[mcp-test] full", "calendar_id": A, "start": f"{D}T10:00", "end": f"{D}T11:30",
         "location": "Eiffel Tower, Champ de Mars, Paris", "latitude": 48.8584, "longitude": 2.2945,
         "notes": "Join: https://zoom.us/j/1234567890", "url": "https://example.com", "availability": "free",
         "travel_time_min": 30, "attachments": [pj],
         "alarms": [{"minutes_before": 15}, {"date": f"{today}T18:00"},
                    {"location": "Test home", "latitude": 48.85, "longitude": 2.35, "when": "leaving"}]},
        {"title": "[mcp-test] all-day span", "calendar_id": A, "start": str(D + dt.timedelta(days=1)), "end": str(D + dt.timedelta(days=3)),
         "alarms": [{"minutes_before": 120}]},
        {"title": "[mcp-test] all day no alarm", "calendar_id": A, "start": str(D), "alarms": []},
        {"title": "[mcp-test] 2nd tuesday", "calendar_id": A, "start": f"{D}T08:00", "duration_min": 30,
         "recurrence": {"frequency": "monthly", "days": ["2tuesday"], "occurrences": 4}},
        {"title": "[mcp-test] last weekday", "calendar_id": A, "start": f"{D}T17:00",
         "recurrence": {"frequency": "monthly", "days": WD[:5], "positions": [-1], "occurrences": 3}},
        {"title": "[mcp-test] mon-wed-fri", "calendar_id": A, "start": f"{D}T12:00",
         "recurrence": {"frequency": "weekly", "days": ["monday", "wednesday", "friday"], "until": str(D + dt.timedelta(days=27))}},
        {"title": "[mcp-test] New York", "calendar_id": A, "start": f"{D}T09:00", "time_zone": "America/New_York"},
        {"title": "", "calendar_id": A, "start": str(D)},
    ]})
    r = res["results"]
    check(res["created"] == 7 and res["failed"] == 1, f"7 created, 1 rejected (empty title): {res['created']}/{res['failed']}")
    check(all("warnings" not in x for x in r[:7]), "no warnings: " + str([x.get("warnings") for x in r if "warnings" in x]))
    FULL, SPAN, NOALARM, TUESDAY, WEEKDAY, MWF, NYC = (x.get("id") for x in r[:7])
    check(r[3].get("start_adjusted") is True or D.weekday() == 1, "2nd tuesday: start adjusted")
    check(r[6].get("start") == ny, f"New York time zone: {r[6].get('start')} expected {ny}")

    print("== Read")
    evs = read([A], detail=True)
    c = next(e for e in evs if e["id"] == FULL)
    check(c.get("location") == "Eiffel Tower, Champ de Mars, Paris" and abs(c.get("latitude", 0) - 48.8584) < 1e-4, f"location text + geolocation: {c.get('location')}")
    check(c.get("notes", "").startswith("Join") and c.get("url") == "https://example.com", "notes, URL")
    check(c.get("video_call") == "https://zoom.us/j/1234567890", f"video call: {c.get('video_call')}")
    check(c.get("availability") == "free" and c.get("travel_time_min") == 30, f"availability, travel time: {c.get('availability')} {c.get('travel_time_min')}")
    check(len(c.get("alarms", [])) == 3, f"3 alarms: {c.get('alarms')}")
    check(c.get("attachments") == [os.path.basename(pj)], f"attachment: {c.get('attachments')}")
    j = next(e for e in evs if e["id"] == SPAN)
    check(j.get("day") == str(D + dt.timedelta(days=1)) and j.get("until") == str(D + dt.timedelta(days=3)), f"all-day span: {j.get('day')} → {j.get('until')}")
    check(j.get("alarms") == [{"minutes_before": 120}], f"all day: only the requested alarm (iCloud default removed): {j.get('alarms')}")
    s = next(e for e in evs if e["id"] == NOALARM)
    check("alarms" not in s, f"all day with alarms []: no alarm: {s.get('alarms')}")
    tuesdays = [e for e in evs if e["id"] == TUESDAY]
    tuesday_dates = [dt.date.fromisoformat(e["start"][:10]) for e in tuesdays]
    check(len(tuesdays) == 4 and all(x.weekday() == 1 and 8 <= x.day <= 14 for x in tuesday_dates), f"2nd tuesday: 4 matching occurrences {tuesday_dates}")
    wkd = [dt.date.fromisoformat(e["start"][:10]) for e in evs if e["id"] == WEEKDAY]
    def last_weekday(x):
        nxt = (x.replace(day=28) + dt.timedelta(days=4)).replace(day=1)
        last = nxt - dt.timedelta(days=1)
        while last.weekday() > 4:
            last -= dt.timedelta(days=1)
        return last
    check(len(wkd) == 3 and all(x == last_weekday(x) for x in wkd), f"last weekday: {wkd}")
    mwf = sorted((e for e in evs if e["id"] == MWF), key=lambda e: e["start"])
    check(len(mwf) >= 10 and all(dt.date.fromisoformat(e["start"][:10]).weekday() in (0, 2, 4) for e in mwf), f"mon-wed-fri: {len(mwf)} matching occurrences")
    check(all("occurrence" in e for e in mwf), "occurrences identified by date")
    check(tuesdays[0].get("recurrence", {}).get("days") == ["2tuesday"], f"rule read back: {tuesdays[0].get('recurrence')}")
    one = call("list_events", {"id": MWF, "occurrence": mwf[1]["occurrence"]})["events"][0]
    check(one["occurrence"] == mwf[1]["occurrence"] and "recurrence" in one, "read a specific occurrence (detail)")
    found = call("list_events", {"calendar_ids": [A], "text": "ZOOM.US"})["events"]
    check([e["id"] for e in found] == [FULL], "text search (case-insensitive) over ±1 year")
    wk = call("list_events", {"calendar_ids": [A], "view": "week", "limit": 3})
    check(len(wk["events"]) == 3 and wk["total"] > 3 and "truncated" in wk, f"week view + limit: {wk['total']}")
    check(call("list_events", {"calendar_ids": [A], "view": "today"})["events"] == [], "today view (nothing today in A)")
    check(call("list_events", {"calendar_ids": [A], "invitations": True})["events"] == [], "pending invitations (none in A)")

    print("== Free slots and conflicts")
    res = call("create_events", {"events": [
        {"title": "[mcp-test] free", "calendar_id": B, "start": f"{D5}T10:00", "end": f"{D5}T11:30", "availability": "free"},
        {"title": "[mcp-test] busy", "calendar_id": B, "start": f"{D5}T14:00", "end": f"{D5}T15:00"},
        {"title": "[mcp-test] overlapping", "calendar_id": B, "start": f"{D5}T14:30", "end": f"{D5}T16:00"},
        {"title": "[mcp-test] short", "calendar_id": B, "start": f"{D5}T16:10", "end": f"{D5}T16:20"},
        {"title": "[mcp-test] all day", "calendar_id": B, "start": str(D5)},
    ]})
    check(res["created"] == 5, "5 events for the slots")
    cr = call("find_free_slots", {"calendar_ids": [B], "start": str(D5), "end": str(D5), "include_weekends": True})["slots"]
    got = [(x["start"][11:], x["end"][11:]) for x in cr]
    check(got == [("09:00", "14:00"), ("16:20", "18:00")], f"slots: {got}")
    cf = call("list_events", {"calendar_ids": [B], "view": "conflicts", "start": str(D5), "end": str(D5)})["events"]
    check(sorted(e["title"] for e in cf) == ["[mcp-test] busy", "[mcp-test] overlapping"], f"conflicts: {[e['title'] for e in cf]}")

    print("== Batch update")
    o3, o6 = mwf[2], mwf[5]
    res = call("update_events", {"updates": [
        {"id": MWF, "occurrence": o3["occurrence"], "title": "[mcp-test] mon-wed-fri (moved)",
         "start": o3["start"][:11] + "14:00", "end": o3["start"][:11] + "15:00"},
        {"id": MWF, "occurrence": o6["occurrence"], "scope": "following", "title": "[mcp-test] mon-wed-fri (following)"},
        {"id": TUESDAY, "occurrence": tuesdays[2]["occurrence"], "scope": "series", "title": "[mcp-test] 2nd tuesday (series)"},
        {"id": FULL, "calendar_id": B, "alarms": [], "travel_time_min": 0, "location": "Office", "url": "", "add_attachments": ["/nonexistent/path.txt"]},
        {"id": SPAN, "start": str(D + dt.timedelta(days=10))},
        {"id": NOALARM, "title": "[mcp-test] now timed", "start": f"{D}T07:00", "duration_min": 45},
        {"id": "nonexistent", "title": "x"},
    ]})
    rr = res["results"]
    check(res["updated"] == 6 and res["failed"] == 1, f"6 updated, 1 unknown id rejected: {res['updated']}/{res['failed']} {[x.get('error') for x in rr if not x['ok']]}")
    check(rr[0]["id"] != MWF, "single occurrence: new detached id")
    check(rr[3].get("warnings") and "not found" in rr[3]["warnings"][0], "missing attachment: warning, no crash")
    evA = read([A], detail=True)
    evB = read([B], detail=True)
    det = [e for e in evA if e["title"] == "[mcp-test] mon-wed-fri (moved)"]
    check(len(det) == 1 and det[0]["start"].endswith("14:00") and det[0].get("modified_occurrence"), "single occurrence updated, moved to 14:00")
    before = [e for e in evA if e["title"] == "[mcp-test] mon-wed-fri"]
    following = [e for e in evA if e["title"] == "[mcp-test] mon-wed-fri (following)"]
    check(len(before) + len(following) + 1 == len(mwf) and len(before) == 4, f"following: {len(before)} before + {len(following)} following + 1 = {len(mwf)}")
    check(len([e for e in evA if e["title"] == "[mcp-test] 2nd tuesday (series)"]) == 4, "whole series renamed from an occurrence")
    cB = next((e for e in evB if e["id"] == FULL), {})
    check(cB.get("location") == "Office" and "latitude" not in cB and "alarms" not in cB and "travel_time_min" not in cB and "url" not in cB,
          f"moved to B, location replaced, alarms/travel time/URL removed: {cB}")
    jj = next(e for e in evA if e["id"] == SPAN)
    check(jj.get("day") == str(D + dt.timedelta(days=10)) and jj.get("until") == str(D + dt.timedelta(days=12)), f"all-day span shifted, duration kept: {jj.get('day')} → {jj.get('until')}")
    h = next(e for e in evA if e["id"] == NOALARM)
    check(h.get("start") == f"{D}T07:00" and h.get("end") == f"{D}T07:45", f"all day → timed: {h.get('start')} {h.get('end')}")

    print("== Deletions")
    following_sorted = sorted(following, key=lambda e: e["start"])
    res = call("delete_events", {"events": [
        {"id": following_sorted[0]["id"], "occurrence": following_sorted[0]["occurrence"]},
        WEEKDAY,
        NYC,
    ]})
    check(res["deleted"] == 3, f"3 deletions: {[x.get('error') for x in res['results'] if not x['ok']]}")
    evA = read([A])
    check(len([e for e in evA if e["title"] == "[mcp-test] mon-wed-fri (following)"]) == len(following) - 1, "a single occurrence deleted")
    check(not any(e["id"] in (WEEKDAY, NYC) for e in evA), "whole series and single event deleted")
    check("contains" in call("delete_calendar", {"id": A}, expect_error=True), "non-empty calendar refused without force")
finally:
    print("== Cleanup")
    for cid in created:
        try:
            call("delete_calendar", {"id": cid, "force": True})
        except Exception as e:  # noqa: BLE001
            print("  cleanup", cid, e)
    if os.path.exists(pj):
        os.remove(pj)
    remaining = call("list_calendars", {"name_contains": "MCP-TEST-"})["calendars"]
    check(remaining == [], f"no MCP-TEST calendar left ({len(remaining)})")
    proc.stdin.close()
    proc.wait(timeout=10)

total = time.time() - T_START
slow = [(n, ms) for i, (n, ms, _) in enumerate(timings) if ms > 500 and i > 0]
print()
print(f"Total duration: {total:.1f} s, {len(timings)} tool calls, 1st call {timings[0][1]} ms, max {max(t[1] for t in timings)} ms, "
      f"max response {max(t[2] for t in timings)} B")
print("Calls > 0.5 s (excluding 1st): " + (", ".join(f"{n} {ms} ms" for n, ms in slow) if slow else "none"))
print("✓ ALL PASSED" if not fails else f"✗ {len(fails)} failure(s):\n  - " + "\n  - ".join(fails))
sys.exit(1 if fails else 0)
