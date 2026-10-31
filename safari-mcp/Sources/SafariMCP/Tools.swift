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
/// Cible d'une action : une seule de ces façons suffit
private let cible: JSON = [
    "ref": s("Ref from snapshot or find (e12): the most reliable"), "selector": s("CSS selector (searched in shadow DOM and same-origin iframes too)"),
    "text": s("Visible text, aria-label, title or alt (accents and case ignored, partial accepted; the interactive ancestor is used)"),
    "role": s("Restrict to a role (button, link, menuitem, tab, checkbox…)"), "label": s("Label or placeholder of a form field"),
    "near": s("Closest element to this text (with role, text or selector)"), "within": s("CSS selector or ref of a zone to search in"),
    "x": n("Viewport X in CSS pixels (with y, instead of a target)"), "y": n("Viewport Y in CSS pixels")]
private let modeProp = e(["auto", "dom", "ax", "native"],
    "auto (default): DOM events, then if the page did not react the Accessibility press, then a real mouse/keyboard event (isTrusted, brings Safari to the front). dom, ax or native forces one level")
private let dialogProps: JSON = ["accept_dialogs": b("Answer confirm() with OK and prompt() with text (true by default); false = Cancel"),
                                 "prompt_text": s("Text returned to prompt() (its default value otherwise)")]
private func avec(_ base: JSON, _ extra: JSON) -> JSON { base.merging(extra) { a, _ in a } }

/// Un seul onglet visé par les outils de page : window_id + index, sinon l'onglet actif de la fenêtre de premier plan
private let tabProps: JSON = ["window_id": n("Window of the tab (with index; active tab of the front window if omitted)"), "index": n("Tab index (with window_id)")]

/// Annotations MCP : seules les lectures sont readOnly, seule la fermeture est destructive,
/// run_js et act sont openWorld (un script ou une suite d'étapes peut soumettre un formulaire ou envoyer des données)
private let lectures: Set<String> = ["list_tabs", "read_page", "page_info", "snapshot", "find", "list_reading_list", "list_bookmarks", "list_history", "list_tab_groups"]
private func annotations(_ nom: String) -> JSON {
    ["readOnlyHint": lectures.contains(nom), "destructiveHint": nom == "close" || nom.hasPrefix("delete_"), "openWorldHint": nom == "run_js" || nom == "act"]
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
        ["name": "act",
         "description": "Runs a sequence of steps in one call, server-side: the way to do anything that takes more than one action (open a menu then pick an item, fill a form and submit, type then format). Each step is {action, ...the parameters of the tool of that name}: click, type, press, select, check, hover, scroll, wait, read (text or field value of a target, or the page as markdown), snapshot, js ({script}), goto ({url}). Every step waits for its target to appear and for the page to settle after it. Stops at the first failing step (or a step whose expect is not met) and returns the steps done, the error and a snapshot of the dialog or screen, so you can continue without another call. Timing of each step included.",
         "inputSchema": obj(avec(tabProps, avec(dialogProps, [
            "steps": arr(["type": "object", "properties": avec(cible, avec(dialogProps, [
                "action": e(["click", "type", "press", "select", "check", "hover", "scroll", "wait", "read", "snapshot", "js", "goto"], "Step type"),
                "value": s("type: text to type"), "clear": b("type: replace the content"), "submit": b("type: press Enter after"),
                "keys": arr(s("Key"), "press: keys or shortcuts, e.g. [\"Enter\"], [\"Cmd+B\"]"), "option": s("select: value or visible text"),
                "checked": b("check: desired state (true by default)"), "to": e(["top", "bottom"], "scroll: where"), "by": n("scroll: pixels (negative = up)"),
                "expect": s("click: text, selector, url: or gone: that must appear; the step fails otherwise"),
                "script": s("js: JavaScript (await accepted)"), "url": s("goto: URL"), "mode": modeProp,
                "button": e(["left", "right", "middle"], "click: button"), "double": b("click: double click"),
                "max_chars": n("read: maximum characters"), "timeout": n("Milliseconds to wait for the target or condition"),
                "ms": n("wait: plain delay"), "gone": s("wait: selector that must disappear")])), "required": ["action"]],
                "The steps, in order")])), ["steps"])],
        ["name": "click",
         "description": "Clicks an element like a person: scrolls it into view, then pointer and mouse events at its center on the element actually there (overlays handled), focus, click. Waits for the page to settle and returns what changed: new visible elements (menus, dialogs) as snapshot lines, URL, focus, intercepted alerts. If the page did not react, escalates by itself to the Accessibility press, then to a real mouse click (isTrusted: needed by draw.io, canvas apps, Google Docs; Safari comes to the front, the answer says so). Right click (context menu), double click and modifiers supported. For several actions in a row, use act. Cannot upload files.",
         "inputSchema": obj(avec(tabProps, avec(cible, avec(dialogProps, [
            "button": e(["left", "right", "middle"], "Button (left by default; right opens the context menu)"), "double": b("Double click"),
            "modifiers": arr(s("cmd, ctrl, alt, shift"), "Keys held during the click"),
            "expect": s("Effect to check: text that must appear, selector, url: part of the URL, or gone: selector that must disappear"),
            "mode": modeProp, "timeout": n("Milliseconds to wait for the target to appear (5000 by default)"),
            "force": b("Click even if the element looks hidden")]))))],
        ["name": "type",
         "description": "Types text into a field: ref, selector, label or text, or the focused element. Inputs and textareas get the value through the native setter plus input and change events (React, Vue and Angular see it); rich editors (contenteditable, ProseMirror, Gmail, Notion) through insertText. clear replaces the content, submit presses Enter. If the field does not show the text, falls back to real keystrokes (Safari comes to the front); mode native for canvas editors such as Google Docs. For a <select> use select; for a file input, uploading is impossible from JavaScript: ask the user.",
         "inputSchema": obj(avec(tabProps, avec(cible, avec(dialogProps, [
            "value": s("Text to type"), "clear": b("Replace the current content"), "submit": b("Press Enter after typing"),
            "mode": e(["auto", "dom", "native"], "auto (default): DOM, then real keystrokes if the field does not show the text"),
            "timeout": n("Milliseconds to wait for the field (5000 by default)")]))), ["value"])],
        ["name": "press",
         "description": "Presses keys or shortcuts in the focused element (or a target): Enter, Tab, Escape, Backspace, Delete, arrows, Home, End, PageUp/Down, F1-F12, letters, with Cmd/Ctrl/Alt/Shift (Cmd+A, Cmd+Z, Cmd+B…). Sends complete KeyboardEvents (key, code, keyCode, which) and performs the default action a real key would (submit a form on Enter, move focus on Tab, bold on Cmd+B in an editor). If nothing reacts, sends the real keys (Safari comes to the front).",
         "inputSchema": obj(avec(tabProps, avec(cible, [
            "keys": arr(s("Key or shortcut, e.g. Enter, Cmd+B, Shift+Tab"), "Keys to press in order"),
            "mode": e(["auto", "dom", "native"], "auto (default), dom or native (real keys)")])), ["keys"])],
        ["name": "select",
         "description": "Chooses an option in a <select> by value or visible text (list for a multiple select), with input and change events. For a custom dropdown (div-based), click it then click the option, or use act.",
         "inputSchema": obj(avec(tabProps, avec(cible, ["option": ["description": "Value or visible text of the option (a list for a multiple select)"],
                                                        "timeout": n("Milliseconds to wait for the field")])), ["option"])],
        ["name": "check",
         "description": "Checks or unchecks a checkbox, radio or switch (native or ARIA), by ref, label or text; does nothing if already in the wanted state. Returns the final state.",
         "inputSchema": obj(avec(tabProps, avec(cible, ["checked": b("Desired state (true by default)"), "mode": modeProp, "timeout": n("Milliseconds to wait for the field")])))],
        ["name": "hover",
         "description": "Moves the pointer over an element to open hover menus or tooltips; returns what appeared. mode native moves the real cursor (Safari comes to the front).",
         "inputSchema": obj(avec(tabProps, avec(cible, ["mode": e(["dom", "native"], "dom (default) or native"), "timeout": n("Milliseconds to wait for the target")])))],
        ["name": "scroll",
         "description": "Scrolls the page (or its main scrolling container, as in Gmail): to: top or bottom, by: pixels, or to an element (ref, selector, text). On an infinite-scroll page, to: bottom waits for new items and says how many elements arrived (loaded_more, new_elements).",
         "inputSchema": obj(avec(tabProps, avec(cible, ["to": e(["top", "bottom"], "Where to go (bottom by default without by)"), "by": n("Pixels to scroll (negative = up)"),
                                                        "wait_more": b("to bottom: wait for new items (true by default)"), "timeout": n("Milliseconds to wait for new items (4000 by default)")])))],
        ["name": "wait",
         "description": "Waits until a condition is true in the page, checking every 30 ms, and survives a navigation in between: selector present and visible, text visible, gone (selector disappeared), text_gone, url containing a string, ready_state, network_idle (no fetch/XHR for idle_ms), js (a JavaScript condition), or ms for a plain delay. Returns what appeared (found, as a snapshot line with its ref). Use it after an action whose effect is slow; click and act already wait for the page to settle.",
         "inputSchema": obj(avec(tabProps, [
            "selector": s("CSS selector that must be present and visible"), "text": s("Text that must be visible"),
            "gone": s("CSS selector that must disappear"), "text_gone": s("Text that must disappear"), "url": s("Part of the URL to reach"),
            "ready_state": e(["interactive", "complete"], "Document state"), "network_idle": b("No fetch or XHR running for idle_ms"),
            "idle_ms": n("Quiet period for network_idle (500 by default)"), "js": s("JavaScript condition (expression or function body returning true)"),
            "ms": n("Plain delay in milliseconds"), "timeout": n("Maximum wait in milliseconds (10000 by default)")]))],
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
        case "act": return try Handlers.agir(a)
        case "click": return try Handlers.cliquer(a)
        case "type": return try Handlers.taper(a)
        case "press": return try Handlers.presser(a)
        case "select": return try Handlers.choisir(a)
        case "check": return try Handlers.cocher(a)
        case "hover": return try Handlers.survoler(a)
        case "scroll": return try Handlers.defiler(a)
        case "wait": return try Handlers.attendre(a)
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
