// Outils exposés : noms, descriptions (quand les utiliser) et schémas d'entrée
import Foundation

private func obj(_ props: JSON, _ required: [String] = []) -> JSON {
    ["type": "object", "properties": props, "required": required]
}
private func s(_ d: String) -> JSON { ["type": "string", "description": d] }
private func b(_ d: String) -> JSON { ["type": "boolean", "description": d] }
private func n(_ d: String) -> JSON { ["type": "number", "description": d] }
private func e(_ values: [String], _ d: String) -> JSON { ["type": "string", "enum": values, "description": d] }
private func arr(_ items: JSON, _ d: String) -> JSON { ["type": "array", "items": items, "description": d] }

private let dateHelp = "YYYY-MM-DD (all day) or YYYY-MM-DDTHH:MM (local time)"

private let alarm = obj([
    "minutes_before": n("Alarm N minutes before the start (all-day events: counted from midnight, 900 = 9 am the day before)"),
    "date": s("Alarm at a date: \(dateHelp)"),
    "location": s("Location alarm: place name (with latitude and longitude)"),
    "latitude": n("Latitude"), "longitude": n("Longitude"),
    "radius": n("Radius in meters (default 100)"),
    "when": e(["arriving", "leaving"], "On arriving or on leaving (default arriving)"),
])

private let recurrence = obj([
    "frequency": e(["daily", "weekly", "monthly", "yearly"], "Frequency"),
    "interval": n("Every N periods (default 1)"),
    "days": arr(s("monday…sunday; rank prefix: 2tuesday = 2nd Tuesday, -1friday = last Friday"), "Days of the week"),
    "days_of_month": arr(n("1 to 31, -1 = last day"), "Days of the month"),
    "months": arr(n("1 to 12"), "Months of the year"),
    "positions": arr(n("1 = first, -1 = last"), "Rank among the matching days of the period (e.g. days monday…friday + positions [-1] = last weekday of the month)"),
    "until": s("Last day included: \(dateHelp)"),
    "occurrences": n("Number of occurrences"),
], ["frequency"])

/// Fields shared by create and update
private let fields: JSON = [
    "title": s("Title"),
    "start": s("Start: \(dateHelp). A date without a time creates an all-day event"),
    "end": s("End: \(dateHelp). All-day events: last day included"),
    "duration_min": n("Duration in minutes, instead of end (default 60)"),
    "all_day": b("All-day event"),
    "time_zone": s("IANA time zone of the event (e.g. America/New_York); start and end are read in this time zone"),
    "location": s("Displayed location (\"\" to clear)"),
    "latitude": n("Location latitude (with longitude: geolocated location)"),
    "longitude": n("Location longitude"),
    "notes": s("Notes (\"\" to clear)"),
    "url": s("URL (\"\" to remove)"),
    "availability": e(["busy", "free", "tentative", "unavailable"], "Displayed availability"),
    "travel_time_min": n("Travel time in minutes (0 to remove)"),
    "alarms": arr(alarm, "Alarms: replaces all alarms, [] to remove them all. Omitted on create: the account's default alarm"),
    "recurrence": ["description": "Recurrence (null to remove it). The start is moved to the first matching date", "anyOf": [recurrence, ["type": "null"]]],
]

private let target: JSON = [
    "id": s("Event identifier"),
    "occurrence": s("Occurrence date (occurrence field returned by list_events), for a recurring event"),
    "scope": e(["this_occurrence", "following", "series"], "Scope on a recurring event: this_occurrence by default if occurrence is given, otherwise series"),
]

private var createFields: JSON {
    var c = fields
    c["calendar_id"] = s("Calendar (default calendar if omitted)")
    c["attachments"] = arr(s("Absolute file path"), "Files to attach")
    return c
}

private var updateFields: JSON {
    var c = fields.merging(target) { a, _ in a }
    c["calendar_id"] = s("Move to this calendar (the whole series for a recurring event)")
    c["add_attachments"] = arr(s("Absolute file path"), "Files to attach")
    return c
}

/// MCP annotations: reads are readOnly, deletions destructive, messages to attendees openWorld
private let lectures: Set<String> = ["list_calendars", "list_events", "find_free_slots"]
private let externes: Set<String> = ["invite", "respond_to_invitations"]
private func annotations(_ nom: String) -> JSON {
    var a: JSON = ["readOnlyHint": lectures.contains(nom), "destructiveHint": nom.hasPrefix("delete_"), "openWorldHint": externes.contains(nom)]
    if nom.hasPrefix("delete_") { a["idempotentHint"] = true }
    return a
}

enum Tools {
    static let definitions: [JSON] = outils.map { o in
        var o = o
        o["annotations"] = annotations(o["name"] as! String)
        return o
    }

    private static let outils: [JSON] = [
        ["name": "list_calendars",
         "description": "Lists calendars (identifier, account, color, read-only, default) and the accounts where calendars can be created. Call it to get calendar_id values.",
         "inputSchema": obj(["name_contains": s("Only keep calendars whose name contains this text")])],
        ["name": "create_calendar",
         "description": "Creates a calendar in an account (the default calendar's account if omitted). Returns its identifier.",
         "inputSchema": obj(["name": s("Name"), "color": s("#RRGGBB or red, orange, yellow, green, blue, purple, brown, gray, pink"),
                             "account": s("Account: name or type (icloud, exchange, on_my_mac, caldav) as returned by list_calendars")], ["name"])],
        ["name": "update_calendar",
         "description": "Renames or recolors a calendar.",
         "inputSchema": obj(["id": s("Calendar identifier"), "name": s("New name"), "color": s("#RRGGBB or color name")], ["id"])],
        ["name": "delete_calendar",
         "description": "Permanently deletes a calendar by identifier. Refuses a non-empty calendar unless force: true.",
         "inputSchema": obj(["id": s("Calendar identifier"), "force": b("Also delete its events")], ["id"])],
        ["name": "list_events",
         "description": "Reads events (recurring events expanded into occurrences): views today, tomorrow, week (7 days), upcoming (30 days), conflicts (overlaps); or a start/end window, calendars, text (title, notes, location), pending invitations, or a specific id. 20 results by default, sorted by start; detail: true adds notes, alarms, recurrence, attendees, attachments.",
         "inputSchema": obj([
            "view": e(["today", "tomorrow", "week", "upcoming", "conflicts"], "Preset view (default week)"),
            "start": s("Window start: \(dateHelp)"),
            "end": s("Window end (excluded): \(dateHelp)"),
            "calendar_ids": arr(s("Calendar identifier"), "Only these calendars"),
            "text": s("Search in title, notes and location (case- and accent-insensitive; ±1 year window if none is given)"),
            "invitations": b("Only invitations I have not responded to"),
            "id": s("A single event (with occurrence for a recurring event); returns the detail"),
            "occurrence": s("Occurrence date, with id"),
            "detail": b("Add notes, URL, alarms, recurrence, attendees, attachments, time zone"),
            "limit": n("Maximum number of results (default 20)"),
         ])],
        ["name": "create_events",
         "description": "Creates one or more events in one call (e.g. a whole schedule): geolocated location, alarms, recurrence (2nd Tuesday, last weekday…), time zone, availability, travel time, attachments. Returns success or failure per item, with identifiers. Does not invite anyone (see invite).",
         "inputSchema": obj(["events": arr(obj(createFields, ["title", "start"]), "Events to create")], ["events"])],
        ["name": "update_events",
         "description": "Updates one or more events by identifier: fields, dates, move to another calendar, attachments. For a recurring event, scope picks this occurrence, the following ones or the whole series. Only the fields given change.",
         "inputSchema": obj(["updates": arr(obj(updateFields, ["id"]), "One entry per event")], ["updates"])],
        ["name": "delete_events",
         "description": "Permanently deletes events by identifier (no trash). For a recurring event: occurrence + scope (this_occurrence, following) or the whole series.",
         "inputSchema": obj(["events": arr(obj(target, ["id"]), "Events to delete")], ["events"])],
        ["name": "find_free_slots",
         "description": "Finds free time slots in my calendars (\"free\" events, all-day events and declined invitations ignored; travel time counted). Use it to find where to place a meeting or a work block.",
         "inputSchema": obj([
            "start": s("Search start: \(dateHelp) (default now)"),
            "end": s("Search end: \(dateHelp) (default 7 days)"),
            "duration_min": n("Minimum duration in minutes (default 30)"),
            "day_start": s("Start of the day HH:MM (default 09:00)"),
            "day_end": s("End of the day HH:MM (default 18:00)"),
            "include_weekends": b("Include Saturday and Sunday (default false)"),
            "calendar_ids": arr(s("Calendar identifier"), "Calendars to take into account (all except Birthdays by default)"),
            "limit": n("Maximum number of slots (default 20)"),
         ])],
        ["name": "invite",
         "description": "Adds attendees to events: invitations are sent immediately by email or iCloud. Use only when the user explicitly asks.",
         "inputSchema": obj(["invitations": arr(obj(target.merging([
            "attendees": arr(obj(["email": s("Email address"), "name": s("Display name")], ["email"]), "People to invite"),
         ]) { a, _ in a }, ["id", "attendees"]), "One entry per event")], ["invitations"])],
        ["name": "respond_to_invitations",
         "description": "Accepts, declines or tentatively accepts received invitations: the response is sent to the organizer. Use only when the user explicitly asks.",
         "inputSchema": obj(["responses": arr(obj(target.merging([
            "response": e(["accepted", "declined", "tentative"], "Response"),
         ]) { a, _ in a }, ["id", "response"]), "One entry per invitation")], ["responses"])],
    ]

    static func call(_ name: String, _ a: JSON) throws -> Any {
        try EK.ready()
        switch name {
        case "list_calendars": return try Handlers.calendriers(a)
        case "create_calendar": return try Handlers.creerCalendrier(a)
        case "update_calendar": return try Handlers.modifierCalendrier(a)
        case "delete_calendar": return try Handlers.supprimerCalendrier(a)
        case "list_events": return try Handlers.evenements(a)
        case "create_events": return try Handlers.creerEvenements(a)
        case "update_events": return try Handlers.modifierEvenements(a)
        case "delete_events": return try Handlers.supprimerEvenements(a)
        case "find_free_slots": return try Handlers.creneauxLibres(a)
        case "invite": return try Handlers.inviter(a)
        case "respond_to_invitations": return try Handlers.repondreInvitations(a)
        default: throw MCPError("unknown tool: \(name)")
        }
    }
}
