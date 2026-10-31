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

private let dateHelp = "YYYY-MM-DD or YYYY-MM-DDTHH:MM (local time)"
private let texteHelp = "Plain-text content: # heading, ## subheading, - bullet, 1. numbered list, **bold**, *italic*"

/// Annotations MCP : seules les lectures sont readOnly, seules les suppressions sont destructive, rien ne sort du Mac
private let lectures: Set<String> = ["list_folders", "list_notes", "read_notes", "list_tags", "open_note"]
private func annotations(_ nom: String) -> JSON {
    // Pas d'idempotentHint : supprimer deux fois une note la purge de la corbeille
    ["readOnlyHint": lectures.contains(nom), "destructiveHint": nom.hasPrefix("delete_"), "openWorldHint": false]
}

enum Tools {
    static let definitions: [JSON] = outils.map { o in
        var o = o
        o["annotations"] = annotations(o["name"] as! String)
        return o
    }

    private static let outils: [JSON] = [
        ["name": "list_folders",
         "description": "Lists accounts and all their folders (nested: parent_id) with id and note count. Call it to find folder_id values. The trash folder is marked trash: true.",
         "inputSchema": obj(["name_contains": s("Only keep folders whose name contains this text")])],
        ["name": "list_notes",
         "description": "Lists or searches notes (title, folder, modification date; pinned, checklist and tags when the database is readable), newest first. Filters: folder (subfolders included), text (title and content), dates, tag, pinned. Excludes “Recently Deleted” unless include_deleted: true or folder_id is given. 20 results by default.",
         "inputSchema": obj([
            "folder_id": s("Limit to this folder"),
            "include_subfolders": b("Include the subfolders of folder_id (true by default)"),
            "text": s("Search in title and content"),
            "modified_since": s("Modified on or after: \(dateHelp)"),
            "modified_before": s("Modified before: \(dateHelp)"),
            "tag": s("Only keep notes with this tag (without #)"),
            "pinned": b("Only keep pinned notes"),
            "include_deleted": b("Include “Recently Deleted”"),
            "limit": n("Maximum number of results (20 by default)"),
         ])],
        ["name": "read_notes",
         "description": "Reads the full content of notes by id: plain text (default) or HTML, dates, attachments (id, name), lock state, tags.",
         "inputSchema": obj(["ids": arr(s("Note id"), "Notes to read"),
                             "format": e(["text", "html"], "text by default; html keeps formatting (images replaced by a placeholder)"),
                             "max_chars": n("Truncate content beyond this length (20000 by default)")], ["ids"])],
        ["name": "create_notes",
         "description": "Creates one or more notes in one call (e.g. from meeting minutes). The title becomes the first line. Returns success or failure per note, with ids. Notes cannot create checkboxes, tags or clickable links this way.",
         "inputSchema": obj(["notes": arr(obj([
            "title": s("Title (first line)"),
            "text": s(texteHelp),
            "html": s("HTML content (instead of text): div, h1-h3, b, i, u, ul/ol/li, table"),
            "folder_id": s("Folder (default folder if omitted)"),
         ], ["title"]), "Notes to create")], ["notes"])],
        ["name": "update_notes",
         "description": "Updates one or more notes by id: title, content (replaced), append at the end, move to a folder. Moving a note from “Recently Deleted” to a folder restores it. Only the fields provided change.",
         "inputSchema": obj(["updates": arr(obj([
            "id": s("Note id"),
            "title": s("New title"),
            "text": s("Replaces the content below the title. " + texteHelp),
            "html": s("Replaces the content below the title, as HTML"),
            "append_text": s("Appends to the end of the note. " + texteHelp),
            "append_html": s("Appends to the end of the note, as HTML"),
            "folder_id": s("Move to this folder (or restore)"),
         ], ["id"]), "One entry per note")], ["updates"])],
        ["name": "delete_notes",
         "description": "Deletes notes by id: they go to “Recently Deleted” (restorable with update_notes folder_id). permanent: true also purges them from the trash.",
         "inputSchema": obj(["ids": arr(s("Note id"), "Notes to delete"),
                             "permanent": b("Also purge from “Recently Deleted” (cannot be undone)")], ["ids"])],
        ["name": "create_folder",
         "description": "Creates a folder (at the account root or inside a parent folder), with optional subfolders. Returns the ids.",
         "inputSchema": obj(["name": s("Name"), "parent_id": s("Create inside this folder"),
                             "account_id": s("Account (default account if omitted; ignored with parent_id)"),
                             "subfolders": arr(s("Name"), "Subfolders to create inside it")], ["name"])],
        ["name": "rename_folder",
         "description": "Renames a folder. (Notes does not allow moving a folder by script.)",
         "inputSchema": obj(["id": s("Folder id"), "name": s("New name")], ["id", "name"])],
        ["name": "delete_folder",
         "description": "Deletes a folder and its subfolders, by id. Their notes go to “Recently Deleted”.",
         "inputSchema": obj(["id": s("Folder id")], ["id"])],
        ["name": "add_attachments",
         "description": "Adds local files (image, PDF, any file) as attachments to notes, in one call.",
         "inputSchema": obj(["attachments": arr(obj(["note_id": s("Note id"), "path": s("Absolute file path")], ["note_id", "path"]),
                                           "Attachments to add")], ["attachments"])],
        ["name": "export_attachments",
         "description": "Saves attachments to a local folder (by id, or all attachments of given notes). Never overwrites an existing file.",
         "inputSchema": obj(["destination": s("Absolute path of the destination folder (created if needed)"),
                             "ids": arr(s("Attachment id"), "Attachments"),
                             "note_ids": arr(s("Note id"), "Export all attachments of these notes")], ["destination"])],
        ["name": "list_tags",
         "description": "Lists tags (#) with their note count, optionally within a folder. Read from the Notes database (Full Disk Access required).",
         "inputSchema": obj(["folder_id": s("Limit to this folder and its subfolders")])],
        ["name": "open_note",
         "description": "Shows a note in the Notes app, in the foreground.",
         "inputSchema": obj(["id": s("Note id")], ["id"])],
    ]

    static func call(_ name: String, _ a: JSON) throws -> Any {
        switch name {
        case "list_folders": return try Handlers.dossiers(a)
        case "list_notes": return try Handlers.notes(a)
        case "read_notes": return try Handlers.lireNotes(a)
        case "create_notes": return try Handlers.creerNotes(a)
        case "update_notes": return try Handlers.modifierNotes(a)
        case "delete_notes": return try Handlers.supprimerNotes(a)
        case "create_folder": return try Handlers.creerDossier(a)
        case "rename_folder": return try Handlers.renommerDossier(a)
        case "delete_folder": return try Handlers.supprimerDossier(a)
        case "add_attachments": return try Handlers.ajouterPiecesJointes(a)
        case "export_attachments": return try Handlers.exporterPiecesJointes(a)
        case "list_tags": return try Handlers.tags(a)
        case "open_note": return try Handlers.ouvrirNote(a)
        default: throw MCPError("unknown tool: \(name)")
        }
    }
}
