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
/// Un seul onglet visé par les outils de page : window_id + index, sinon l'onglet actif de la fenêtre de premier plan
private let tabProps: JSON = ["window_id": n("Window of the tab (with index; active tab of the front window if omitted)"), "index": n("Tab index (with window_id)")]

/// Annotations MCP : seules les lectures sont readOnly, seule la fermeture est destructive,
/// seul run_js est openWorld (un script peut soumettre un formulaire ou envoyer des données)
private let lectures: Set<String> = ["list_tabs", "read_page", "page_info", "snapshot", "find", "list_reading_list", "list_bookmarks", "list_history", "list_tab_groups"]
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
         "description": "Reads the content of one or more tabs. markdown (default): the main content (article, main; menus, cookie banners and footers removed) with headings, lists, Markdown tables, compact links, image alt text and code; full: true for the whole page, selector for one zone. text: raw visible text, links: the links, html: current HTML. Use it to summarize, compare or extract; use snapshot instead to act on the page. A truncated answer gives length: call again with offset to read the rest. A PDF tab returns the text Safari extracts.",
         "inputSchema": obj(["tabs": refs, "format": e(["markdown", "text", "links", "html"], "markdown by default"),
                             "selector": s("markdown: only this zone (CSS selector)"), "full": b("markdown: the whole page instead of the main content"),
                             "links": b("markdown: keep link targets (true by default)"),
                             "max_chars": n("Truncate each page to this many characters (8000 by default)"), "offset": n("Start at this character (to read past a truncation)")])],
        ["name": "run_js",
         "description": "Runs synchronous JavaScript in one or more tabs and returns the result (objects converted to JSON). A single expression is enough; otherwise a function body with return. For clicking, filling in, extracting.",
         "inputSchema": obj(["script": s("JavaScript code"), "tabs": refs], ["script"])],
        ["name": "capture_page",
         "description": "Saves an image (PNG, or JPEG if path ends in .jpg) of a tab: what is visible, or the whole page with full_page. For keeping a page as proof or attaching it to a reminder or a note. The page is redrawn off screen from the tab's current content (no Screen Recording permission; works with the Mac locked); an image from another site that requires a login may be missing. Returns the file path.",
         "inputSchema": obj(["window_id": n("Window (active tab of the front window if omitted)"), "index": n("Tab index in the window"),
                             "full_page": b("Whole page instead of the visible part (capped at 20000 px tall)"),
                             "path": s("Absolute path of the image file (default: ~/Pictures/Safari captures/<title> <date>.png)")])],
        ["name": "page_info",
         "description": "First call on an unknown page: what it is and how to drive it, in one cheap call. URL, title, readyState, frameworks and editors (React, Vue, Angular, Svelte, draw.io/mxGraph, Monaco, CodeMirror, ProseMirror, Google Docs canvas), page type (article, application, form, pdf, login, error, captcha, canvas app), iframes and shadow roots, scroll height and position (infinite scroll likely or not), open dialogs, focused element, selected text, alerts intercepted so far. Then use snapshot to see the controls, or read_page to read.",
         "inputSchema": obj(tabProps)],
        ["name": "snapshot",
         "description": "Compact accessibility tree of the page, one line per element: ref, role, accessible name, states [checked, expanded, collapsed, disabled, selected, focused…] and = value for fields. Default: interactive elements and headings in DOM order (open shadow DOM and same-origin iframes included; cross-origin iframes flagged). Refs (e12) are reused by click, type, select, check, hover, scroll, find and act until the page reloads. Use it before acting on a page you have not seen; use read_page to read text, find to locate one element.",
         "inputSchema": obj(tabProps.merging([
            "all": b("Every element with a role or text, not only interactive elements and headings"),
            "viewport_only": b("Only elements currently on screen"),
            "selector": s("CSS selector of a zone to limit the snapshot to"), "ref": s("Ref of a zone (e.g. a dialog) to limit the snapshot to"),
            "urls": b("Add link targets"),
            "max_chars": n("Size of a page of lines (8000 by default)"), "offset": n("Continue from this offset (next_offset of the previous call)")]) { a, _ in a })],
        ["name": "find",
         "description": "Locates elements by visible text (accents and case ignored, partial words accepted), role, CSS selector, field label, or proximity to a text (near: \"Password\" finds the field next to it). Returns ref, role, name, rect, and whether it is visible, off-screen, covered (by what) or hidden (and why). Use it when you know what you look for; snapshot to discover the page.",
         "inputSchema": obj(tabProps.merging([
            "text": s("Visible text, aria-label, title, placeholder or alt (case and accents ignored, partial words accepted)"),
            "role": s("Role: button, link, textbox, checkbox, combobox, menuitem, tab, heading, clickable…"),
            "selector": s("CSS selector"), "label": s("Label of a form field (label, placeholder, aria-label)"),
            "near": s("Rank by distance to the element showing this text (e.g. the field next to \"Password\")"),
            "within": s("CSS selector or ref of a zone to search in"), "limit": n("Maximum number (10 by default)")]) { a, _ in a })],
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
        case "page_info": return try Handlers.pageInfo(a)
        case "snapshot": return try Handlers.snapshot(a)
        case "find": return try Handlers.trouver(a)
        case "capture_page": return try Capture.capturer(a)
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
