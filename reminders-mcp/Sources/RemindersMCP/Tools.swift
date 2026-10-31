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

private let alarme = obj([
    "date": s("Alert at a date: \(dateHelp)"),
    "minutes_before": n("Alert N minutes before the due date"),
    "location": s("Location alert: place name (requires latitude and longitude)"),
    "latitude": n("Latitude of the place"),
    "longitude": n("Longitude of the place"),
    "radius": n("Radius in meters (default 100)"),
    "when": e(["arrival", "departure"], "Trigger on arrival or departure (default arrival)"),
])

private let recurrence = obj([
    "frequency": e(["daily", "weekly", "monthly", "yearly"], "Frequency"),
    "interval": n("Every N periods (default 1)"),
    "days": arr(e(["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"], "Day"), "Days of the week (weekly frequency)"),
    "until": s("End date: \(dateHelp)"),
    "occurrences": n("Number of occurrences"),
], ["frequency"])

/// Champs communs à la création et à la modification
private let champs: JSON = [
    "title": s("Title"),
    "notes": s("Notes (\"\" to clear)"),
    "due": s("Due date: \(dateHelp). With a time, an alert is set at the due time, as in the app. \"\" to clear"),
    "start": s("Start date: \(dateHelp). \"\" to clear"),
    "priority": e(["high", "medium", "low", "none"], "Priority"),
    "flagged": b("Flag"),
    "url": s("URL shown in the reminder (\"\" to remove)"),
    "section_id": s("Section of the list (see the list_sections tool; \"\" to take it out of its section)"),
    "alarms": arr(alarme, "Alerts (replaces all existing alerts; [] to remove them all)"),
    "recurrence": ["description": "Recurrence (null to remove it). Requires a due date.", "anyOf": [recurrence, ["type": "null"]]],
]

private var champsCreation: JSON {
    var c = champs
    c["list_id"] = s("List (default list if omitted; ignored for a subtask)")
    c["tags"] = arr(s("Tag without #"), "Tags")
    c["parent_id"] = s("Create as a subtask of this reminder")
    c["subtasks"] = arr(obj(champs, ["title"]), "Subtasks to create under this reminder (one level only)")
    return c
}

private var champsModification: JSON {
    var c = champs
    c["id"] = s("Reminder ID")
    c["list_id"] = s("Move to this list (subtasks follow)")
    c["parent_id"] = s("Make this reminder a subtask of this parent (\"\" to detach it)")
    c["add_tags"] = arr(s("Tag without #"), "Tags to add")
    c["remove_tags"] = arr(s("Tag without #"), "Tags to remove")
    return c
}

private let colorHelp = "#RRGGBB or red, orange, yellow, green, blue, purple, brown, gray, pink"
private let statusEnum = e(["incomplete", "completed", "all"], "Default incomplete")

/// Annotations MCP : seules les lectures sont readOnly, seules les suppressions sont destructive
private let lectures: Set<String> = ["list_lists", "list_reminders", "list_sections", "list_tags"]
private func annotations(_ nom: String) -> JSON {
    var a: JSON = ["readOnlyHint": lectures.contains(nom), "destructiveHint": nom.hasPrefix("delete_"), "openWorldHint": false]
    if nom == "complete_reminders" { a["idempotentHint"] = true }
    return a
}

enum Tools {
    static let definitions: [JSON] = outils.map { o in
        var o = o
        o["annotations"] = annotations(o["name"] as! String)
        return o
    }

    private static let outils: [JSON] = [
        ["name": "list_lists",
         "description": "Lists Reminders lists with their ID, account, color, group and number of incomplete reminders. Call this first to get list_id values. Groups (folders of lists) have group: true.",
         "inputSchema": obj(["name_contains": s("Only keep lists whose name contains this text")])],
        ["name": "create_list",
         "description": "Creates a list, or a group of lists (group: true). Returns its ID.",
         "inputSchema": obj(["name": s("Name"), "color": s(colorHelp),
                             "group": b("Create a group (folder of lists) instead of a list"),
                             "group_id": s("Create the list inside this group")], ["name"])],
        ["name": "update_list",
         "description": "Renames a list or group, changes its color, puts it into a group or takes it out.",
         "inputSchema": obj(["id": s("List or group ID"), "name": s("New name"), "color": s("#RRGGBB or color name"),
                             "group_id": s("Put the list into this group (\"\" to take it out of its group)")], ["id"])],
        ["name": "delete_list",
         "description": "Permanently deletes a list (and its reminders) or an empty group, by ID. Refuses a non-empty list unless force: true.",
         "inputSchema": obj(["id": s("List or group ID"), "force": b("Also delete the reminders it contains")], ["id"])],
        ["name": "list_sections",
         "description": "Lists the sections of a list (ID and name), for placing reminders with section_id.",
         "inputSchema": obj(["list_id": s("List ID")], ["list_id"])],
        ["name": "create_section",
         "description": "Creates a section in a list. Returns its ID.",
         "inputSchema": obj(["list_id": s("List ID"), "name": s("Section name")], ["list_id", "name"])],
        ["name": "delete_section",
         "description": "Deletes a section by ID. Its reminders stay in the list, outside any section.",
         "inputSchema": obj(["id": s("Section ID")], ["id"])],
        ["name": "list_reminders",
         "description": "Reads reminders with filters: built-in views (today includes overdue, overdue, week, scheduled, flagged, recently_completed), lists, text, tag, dates, status, subtasks of a parent. Returns IDs, due dates, tags, flag, subtasks, section, etc. 100 results by default, sorted by due date.",
         "inputSchema": obj([
            "view": e(["today", "overdue", "week", "scheduled", "flagged", "recently_completed"], "Built-in view"),
            "list_ids": arr(s("List ID"), "Limit to these lists"),
            "status": statusEnum,
            "text": s("Search in title and notes (case- and accent-insensitive)"),
            "tag": s("Only keep this tag (without #)"),
            "flagged": b("Only keep reminders with (true) or without (false) a flag"),
            "due_before": s("Due strictly before: \(dateHelp)"),
            "due_after": s("Due on or after: \(dateHelp)"),
            "no_due": b("Only keep reminders without a due date"),
            "parent_id": s("Only return the subtasks of this reminder"),
            "limit": n("Maximum number of results (default 100)"),
         ])],
        ["name": "create_reminders",
         "description": "Creates one or more reminders in a single call (e.g. all the action items from meeting notes), with subtasks, tags, flag, alerts, recurrence, URL, section. Returns success or failure per item, with IDs.",
         "inputSchema": obj(["reminders": arr(obj(champsCreation, ["title"]), "Reminders to create")], ["reminders"])],
        ["name": "update_reminders",
         "description": "Updates one or more reminders by ID: fields, tags, flag, move to another list (subtasks included), section, attach to a parent. Only the fields provided change. To complete, use complete_reminders.",
         "inputSchema": obj(["updates": arr(obj(champsModification, ["id"]), "One entry per reminder")], ["updates"])],
        ["name": "complete_reminders",
         "description": "Marks reminders as completed (or reopens them with completed: false). Completing a recurring reminder creates the next occurrence.",
         "inputSchema": obj(["ids": arr(s("ID"), "Reminders"), "completed": b("Default true; false to reopen")], ["ids"])],
        ["name": "delete_reminders",
         "description": "Permanently deletes reminders by ID (no trash). Deleting a parent also deletes its subtasks.",
         "inputSchema": obj(["ids": arr(s("ID"), "Reminders to delete")], ["ids"])],
        ["name": "add_image",
         "description": "Attaches an image (local PNG, JPEG, HEIC… file) to a reminder.",
         "inputSchema": obj(["id": s("Reminder ID"), "path": s("Absolute path of the image file")], ["id", "path"])],
        ["name": "list_tags",
         "description": "Lists the tags in use with the number of reminders carrying each (incomplete by default).",
         "inputSchema": obj(["list_ids": arr(s("List ID"), "Limit to these lists"),
                             "status": statusEnum])],
    ]

    static func call(_ name: String, _ a: JSON) throws -> Any {
        try EK.ready()
        switch name {
        case "list_lists": return try Handlers.listes(a)
        case "create_list": return try Handlers.creerListe(a)
        case "update_list": return try Handlers.modifierListe(a)
        case "delete_list": return try Handlers.supprimerListe(a)
        case "list_sections": return try Handlers.sections(a)
        case "create_section": return try Handlers.creerSection(a)
        case "delete_section": return try Handlers.supprimerSection(a)
        case "list_reminders": return try Handlers.rappels(a)
        case "create_reminders": return try Handlers.creerRappels(a)
        case "update_reminders": return try Handlers.modifierRappels(a)
        case "complete_reminders": return try Handlers.terminerRappels(a)
        case "delete_reminders": return try Handlers.supprimerRappels(a)
        case "add_image": return try Handlers.ajouterImage(a)
        case "list_tags": return try Handlers.tags(a)
        default: throw MCPError("unknown tool: \(name)")
        }
    }
}
