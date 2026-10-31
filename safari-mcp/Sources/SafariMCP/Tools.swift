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
private let ref: JSON = obj(["window_id": n("Window identifier (see list_tabs)"), "index": n("Tab index in the window, starting at 1")], ["window_id", "index"])
private let refs = arr(ref, "Target tabs (active tab of the front window if omitted)")

/// Annotations MCP : seules les lectures sont readOnly, seule la fermeture est destructive,
/// seul run_js est openWorld (un script peut soumettre un formulaire ou envoyer des données)
private let lectures: Set<String> = ["list_tabs", "read_page", "list_reading_list", "list_bookmarks", "list_history", "list_tab_groups"]
private func annotations(_ nom: String) -> JSON {
    ["readOnlyHint": lectures.contains(nom), "destructiveHint": nom == "close" || nom.hasPrefix("delete_"), "openWorldHint": nom == "run_js"]
}

enum Tools {
    static let definitions: [JSON] = outils.map { o in
        var o = o
        o["annotations"] = annotations(o["name"] as! String)
        return o
    }

    private static let outils: [JSON] = [
        ["name": "list_tabs",
         "description": "Lists open Safari windows and their tabs (window_id, index, title, URL, active). Call this first to target tabs. 50 tabs by default.",
         "inputSchema": obj(["window_id": n("Only this window"), "text": s("Only keep tabs whose title or URL contains this text"),
                             "limit": n("Maximum number of tabs (50 by default)")])],
        ["name": "open",
         "description": "Opens one or more URLs in new tabs: in a given window, in the front window (default), in a new window or in a private window. Returns the window_id and index of each tab.",
         "inputSchema": obj(["urls": arr(s("URL (https:// added if missing; local path accepted)"), "URLs to open"),
                             "window_id": n("Open in this window"), "new_window": b("Open in a new window"),
                             "private": b("Open in a new private window (no history; Safari comes to the front)"),
                             "wait": b("Wait for loading to finish and return the titles")], ["urls"])],
        ["name": "navigate",
         "description": "Acts on existing tabs: go to a URL, reload, back, forward, or activate (show the tab and bring its window to the front).",
         "inputSchema": obj(["actions": arr(obj(["window_id": n("Window"), "index": n("Tab"), "url": s("Go to this URL"),
                                                 "action": e(["url", "reload", "back", "forward", "activate"], "url by default when url is given")],
                                                ["window_id", "index"]), "One entry per tab"),
                             "wait": b("Wait for loading to finish and return the titles")], ["actions"])],
        ["name": "close",
         "description": "Closes tabs (by window_id and index) and/or whole windows. expected_url avoids closing a tab that has changed since it was read.",
         "inputSchema": obj(["tabs": arr(obj(["window_id": n("Window"), "index": n("Tab"), "expected_url": s("Only close if the URL starts with this")], ["window_id", "index"]), "Tabs to close"),
                             "windows": arr(n("Identifier"), "Windows to close with all their tabs")])],
        ["name": "read_page",
         "description": "Reads the content of one or more tabs: visible text (default), links, or current HTML. For summarizing, comparing or extracting.",
         "inputSchema": obj(["tabs": refs, "format": e(["text", "links", "html"], "text by default"),
                             "max_chars": n("Truncate each page to this many characters (8000 by default)")])],
        ["name": "run_js",
         "description": "Runs synchronous JavaScript in one or more tabs and returns the result (objects converted to JSON). A single expression is enough; otherwise a function body with return. For clicking, filling in, extracting.",
         "inputSchema": obj(["script": s("JavaScript code"), "tabs": refs], ["script"])],
        ["name": "list_reading_list",
         "description": "Reads the Reading List (title, URL, date added, read), newest first. 20 items by default.",
         "inputSchema": obj(["text": s("Filter on title, URL or preview"), "unread_only": b("Only unread items"),
                             "include_preview": b("Include the preview text"), "limit": n("Maximum number (20 by default)")])],
        ["name": "add_to_reading_list",
         "description": "Adds one or more URLs to the Reading List. Safari replaces the title with the page's own.",
         "inputSchema": obj(["items": arr(obj(["url": s("URL"), "title": s("Title (optional)"), "preview": s("Preview text (optional)")], ["url"]), "Items to add")], ["items"])],
        ["name": "list_bookmarks",
         "description": "Searches bookmarks: title, URL, folder. With folders: true, lists the folders. 50 results by default.",
         "inputSchema": obj(["text": s("Filter on title or URL"), "folder": s("Only in folders whose path contains this text"),
                             "folders": b("List folders instead of bookmarks"), "limit": n("Maximum number (50 by default)")])],
        ["name": "list_history",
         "description": "Searches browsing history: visited pages (title, URL, last visit, visit count), most recent first. 20 by default.",
         "inputSchema": obj(["text": s("Filter on title or URL"), "domain": s("Only this domain (e.g. nytimes.com)"),
                             "since": s("Visits from: \(dateHelp)"), "until": s("Visits before: \(dateHelp)"),
                             "limit": n("Maximum number (20 by default)")])],
        ["name": "list_tab_groups",
         "description": "Lists tab groups (name, tab count, open or not), or the tabs of one group with group_id. Opening a group is done in Safari; to delete: delete_tab_groups.",
         "inputSchema": obj(["text": s("Filter on group name"), "group_id": n("List the tabs of this group"),
                             "include_unnamed": b("Include the unnamed groups specific to each window")])],
        ["name": "delete_from_reading_list",
         "description": "Permanently deletes Reading List items, by exact URL (see list_reading_list). Works through Safari's sidebar in a dedicated window, closed at the end (requires Accessibility access).",
         "inputSchema": obj(["urls": arr(s("Exact URL of the item"), "Items to delete")], ["urls"])],
        ["name": "delete_history",
         "description": "Permanently deletes pages from history (each page with all its visits, like Safari does): by exact URL or by text (title or URL), optionally restricted to pages visited during a range of days. Returns the number of pages and visits removed. Works through Safari's History view in a dedicated window (requires Accessibility access).",
         "inputSchema": obj(["urls": arr(s("Exact URL"), "Pages to delete"), "text": s("Pages whose title or URL contains this text"),
                             "since": s("Only pages visited from this day: YYYY-MM-DD"), "until": s("… and before this day (excluded): YYYY-MM-DD")])],
        ["name": "delete_tab_groups",
         "description": "Permanently deletes tab groups (and their tabs) by group_id (see list_tab_groups). Refuses a group shown in an open window. Works through Safari's sidebar in a dedicated window (requires Accessibility access).",
         "inputSchema": obj(["group_ids": arr(n("Group identifier"), "Groups to delete")], ["group_ids"])],
    ]

    static func call(_ name: String, _ a: JSON) throws -> Any {
        switch name {
        case "list_tabs": return try Handlers.onglets(a)
        case "open": return try Handlers.ouvrir(a)
        case "navigate": return try Handlers.naviguer(a)
        case "close": return try Handlers.fermer(a)
        case "read_page": return try Handlers.lirePage(a)
        case "run_js": return try Handlers.executerJS(a)
        case "list_reading_list": return try Handlers.listeDeLecture(a)
        case "add_to_reading_list": return try Handlers.ajouterListeDeLecture(a)
        case "list_bookmarks": return try Handlers.favoris(a)
        case "list_history": return try Handlers.historique(a)
        case "list_tab_groups": return try Handlers.groupesOnglets(a)
        case "delete_from_reading_list": return try Suppressions.listeDeLecture(a)
        case "delete_history": return try Suppressions.historique(a)
        case "delete_tab_groups": return try Suppressions.groupesOnglets(a)
        default: throw MCPError("unknown tool: \(name)")
        }
    }
}
