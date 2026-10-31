// Outils exposés : noms, descriptions (quand les utiliser) et schémas d'entrée
import Foundation

private func obj(_ props: JSON, _ required: [String] = []) -> JSON { ["type": "object", "properties": props, "required": required] }
private func s(_ d: String) -> JSON { ["type": "string", "description": d] }
private func b(_ d: String) -> JSON { ["type": "boolean", "description": d] }
private func n(_ d: String) -> JSON { ["type": "number", "description": d] }
private func e(_ values: [String], _ d: String) -> JSON { ["type": "string", "enum": values, "description": d] }
private func arr(_ items: JSON, _ d: String) -> JSON { ["type": "array", "items": items, "description": d] }
private func avec(_ base: JSON, _ extra: JSON) -> JSON { base.merging(extra) { a, _ in a } }

private let app = s("App: name as shown (Safari, TextEdit, Finder, Réglages Système…), bundle id or pid")
private let keep = b("Leave the target app in front afterwards (default: the previous app gets the front back; kept automatically while a menu is open)")
/// Cible d'une action : une seule de ces façons suffit
private let cible: JSON = [
    "ref": s("Ref from find, windows or dialogs (a12): the most reliable"),
    "app": app, "title": s("Title, label or description of the element in that app (exact first, then partial; sheets and dialogs searched first)"),
    "role": s("With title: restrict to a role (button, checkbox, textfield, link…)"),
    "x": n("Screen X in points (with y), as given by find or computed from screenshot"), "y": n("Screen Y in points"),
]

/// Annotations MCP : lectures en readOnly ; app (quit, force) destructive ; les actions agissent sur des apps arbitraires
private let lectures: Set<String> = ["screenshot", "windows", "find", "dialogs"]
private func annotations(_ nom: String) -> JSON {
    ["readOnlyHint": lectures.contains(nom), "destructiveHint": nom == "app", "openWorldHint": !lectures.contains(nom)]
}

enum Tools {
    static let definitions: [JSON] = outils.map { o in
        var o = o
        o["annotations"] = annotations(o["name"] as! String)
        return o
    }

    static let outils: [JSON] = [
        ["name": "screenshot",
         "description": "Image (PNG) of the screen, a window (with its sheets) or a region. Use it when the Accessibility tree is not enough: canvas, images, charts, visual layout, or to check what a person would see. The caption gives the mapping to screen points for click x/y. Default: main display, 1 image pixel per screen point, longest side capped at 1568 px. Needs the Screen Recording permission given at install.",
         "inputSchema": obj(["window": n("Window id (id= in windows)"), "app": app, "title": s("With app: window whose title contains this"),
                             "ref": s("Ref of a window or of an element in it"), "display": n("Display number from windows (1 = main)"),
                             "region": obj(["x": n("Left, screen points"), "y": n("Top"), "width": n("Width"), "height": n("Height")], ["width", "height"]),
                             "scale": n("Image pixels per screen point (0.1 to the display's own, 2 on Retina)"),
                             "cursor": b("Draw the pointer"), "path": s("Also save the PNG to this file")])],
        ["name": "windows",
         "description": "Running apps and their windows: app, pid, front or hidden, then per window its ref, title, position and size in screen points, id (for screenshot), minimized, focused, +sheet when a sheet is open. Also the displays. Cheap: call it first to see what is on the Mac.",
         "inputSchema": obj(["app": s("Only this app"), "all": b("Also background agents that have a window on screen")])],
        ["name": "find",
         "description": "Accessibility tree of an app (front app by default), a window or an element: one line per element with ref, role, title, value, position and size, disabled/focused/selected. Empty containers are skipped. text and role filter to matching elements (flat list). Refs stay valid while the element exists: pass them to click, type, scroll, drag. Web content is included (Safari pages, Electron apps).",
         "inputSchema": obj(["app": app, "window": s("Window title (partial), ref or id"), "ref": s("Subtree under this element"),
                             "text": s("Only elements whose title, value, description or identifier contains this (accents and case ignored)"),
                             "role": s("Only these roles, comma separated: button, textfield, checkbox, menuitem, link, statictext, row…"),
                             "menu_bar": b("Include the app's menu bar (the menu tool is simpler)"), "web": b("Descend into web areas (default true)"),
                             "depth": n("Maximum depth (default 40)"), "limit": n("Maximum lines (default 250)")])],
        ["name": "dialogs",
         "description": "Every open alert, sheet, modal panel and system prompt, in all apps: app, kind, ref, title and text, buttons (the default marked *) with refs, text fields with values. Use it whenever an app seems stuck or after an action that may ask something (save, download, quit, open a file). Answer with answer_dialog.",
         "inputSchema": obj(["app": s("Only this app")])],
        ["name": "click",
         "description": "Clicks like a person: by ref, by title in an app (button, checkbox, link, tab…), or at screen x/y. A plain left click uses the Accessibility press first (no pointer move, the app stays where it is); double, triple, right or modified clicks, real: true, or elements without a press are real mouse events, the app being brought to the front just for the click. Reports any dialog the click opened.",
         "inputSchema": obj(avec(cible, ["button": e(["left", "right", "middle"], "Mouse button (default left)"), "count": n("2 = double click, 3 = triple"),
                                         "modifiers": arr(s("cmd, shift, alt, ctrl"), "Keys held during the click"),
                                         "real": b("Always a real mouse event (canvas, drag handles, apps that ignore the Accessibility press)"), "keep_front": keep]))],
        ["name": "type",
         "description": "Types text with real key events into an app (its focused field) or into the element of ref (focused first). Any character, any keyboard layout; new lines and tabs are real Return and Tab keys. clear: select all and delete first; submit: press Return after. app or ref is required (never typed into whatever happens to be in front).",
         "inputSchema": obj(["text": s("Text to type"), "app": app, "ref": s("Field to type into"), "clear": b("Replace the field's content"),
                             "submit": b("Press Return after"), "keep_front": keep], ["text"])],
        ["name": "press",
         "description": "Presses keys or shortcuts in an app with real key events: \"cmd+s\", \"enter\", \"escape\", \"shift+tab\", \"cmd+shift+n\", arrows, f1-f15. Several keys run in order; repeat repeats the sequence. app or ref is required.",
         "inputSchema": obj(["keys": ["description": "Key or shortcut, or a list of them", "anyOf": [["type": "string"], ["type": "array", "items": ["type": "string"]]]],
                             "app": app, "ref": s("Element to focus first"), "repeat": n("Repeat the sequence (default 1, max 50)"), "keep_front": keep], ["keys"])],
        ["name": "scroll",
         "description": "Scrolls with the real mouse wheel over a ref, a point, or the middle of an app's front window. dy lines (positive = down, default 5), dx columns (positive = right).",
         "inputSchema": obj(avec(cible, ["dy": n("Lines, positive = down"), "dx": n("Columns, positive = right"), "keep_front": keep]))],
        ["name": "drag",
         "description": "Drags with the real mouse from one point or ref to another (move a file, a slider, a window, select text, draw). The source app is brought to the front for the drag.",
         "inputSchema": obj(["from_ref": s("Start element"), "from_x": n("Start screen X"), "from_y": n("Start screen Y"),
                             "to_ref": s("End element"), "to_x": n("End screen X"), "to_y": n("End screen Y"), "app": app,
                             "button": e(["left", "right"], "Mouse button"), "modifiers": arr(s("cmd, shift, alt, ctrl"), "Keys held (alt = copy in Finder)"),
                             "duration": n("Seconds for the move (default 0.4)"), "keep_front": keep])],
        ["name": "move",
         "description": "Moves the pointer to a ref or a point (hover: tooltips, menus that open on hover, revealed buttons) and says what is under it.",
         "inputSchema": obj(cible)],
        ["name": "answer_dialog",
         "description": "Answers an open alert, sheet or panel in any app by its button name: Allow/Autoriser, Save/Enregistrer, Cancel/Annuler, OK, Delete/Supprimer, Don't Save, Replace, Open, Leave Page… (English and French equivalents accepted, also \"default\" and \"cancel\"). fill types a value into its first text field first (file name in Save As). Without app, the only dialog that has this button is used. wait seconds for the dialog to appear. Uses the Accessibility press, a real click if refused, and checks it closed; reports any dialog that follows.",
         "inputSchema": obj(["button": s("Button title, or default, or cancel"), "app": s("App showing the dialog"), "contains": s("Dialog whose title or text contains this"),
                             "ref": s("Dialog or button ref from dialogs"), "fill": s("Value for the first text field (e.g. file name)"),
                             "wait": n("Seconds to wait for a matching dialog (max 30)")], ["button"])],
        ["name": "watch_dialogs",
         "description": "Standing policy, kept while the server runs: every new dialog that matches a rule (app, text it contains) is answered at once with the first of its buttons that exists, without any call. Set it before an action that will raise dialogs (downloads: [Autoriser] then [Enregistrer]; quitting apps: [Ne pas enregistrer]). Never put destructive answers in broad rules. Returns the rules and the log of what was answered since the last call; wait blocks until count new answers (or timeout).",
         "inputSchema": obj(["rules": arr(obj(["app": s("App name or bundle id (any if omitted)"), "contains": s("Only dialogs whose title or text contains this"),
                                                "button": s("Button to press"), "buttons": arr(s("Button"), "Buttons to try in order")]), "Rules, first match wins"),
                             "mode": e(["add", "replace", "clear", "status"], "add (default with rules), replace all rules, clear all, status (default without rules)"),
                             "wait": n("Seconds to wait for new answers (max 120)"), "count": n("Answers to wait for (default 1)")])],
        ["name": "app",
         "description": "Launches (in the background unless activate: true; open: files or URLs to open with it), activates, hides or quits an app. Quit asks the app like Cmd+Q: if it asks to save, the dialog is returned to answer with answer_dialog; force: true kills it without saving. Reports the app's windows and any dialog.",
         "inputSchema": obj(["app": s("App name (as in Finder, localized or not), bundle id, path, or pid when running"),
                             "action": e(["launch", "activate", "hide", "quit"], "Default launch"), "activate": b("With launch: bring it to the front"),
                             "open": arr(s("Path or URL"), "With launch: documents or URLs to open"), "force": b("With quit: kill it, unsaved work is lost")], ["app"])],
        ["name": "menu",
         "description": "Menu bar of an app: without path, lists the menus; with a path to a menu (\"Fichier\", \"Fichier > Exporter\"), lists its items with shortcuts, checks and disabled state; with a path to an item (\"Fichier > Exporter au format PDF…\"), clicks it. Titles are matched without case, accents or trailing …. The app is brought to the front for the click, then the previous app gets the front back. Reports any dialog it opened.",
         "inputSchema": obj(["app": app, "path": ["description": "\"Menu > Item > Subitem\" or a list of titles", "anyOf": [["type": "string"], ["type": "array", "items": ["type": "string"]]]],
                             "keep_front": keep], ["app"])],
    ]

    static func call(_ name: String, _ a: JSON) throws -> Any {
        switch name {
        case "screenshot": return try Screen.screenshot(a)
        case "windows": return try Screen.windows(a)
        case "find": return try Tree.find(a)
        case "dialogs": return try Tree.dialogs(a)
        case "click": return try Act.click(a)
        case "type": return try Act.type(a)
        case "press": return try Act.press(a)
        case "scroll": return try Act.scroll(a)
        case "drag": return try Act.drag(a)
        case "move": return try Act.move(a)
        case "answer_dialog": return try Answer.answer(a)
        case "watch_dialogs": return try Answer.watch(a)
        case "app": return try AppTool.run(a)
        case "menu": return try Menu.run(a)
        case "_inspect": return try Debug.inspect(a)   // débogage, non listé
        case "_cg": return try Debug.cg(a)
        default: throw MCPError("unknown tool: \(name)")
        }
    }
}
