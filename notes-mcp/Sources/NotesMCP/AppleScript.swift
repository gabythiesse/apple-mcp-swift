// Voie AppleScript : NSAppleScript dans le process, un script par appel d'outil qui traite tout le lot
import Foundation

enum AS {
    /// Handlers communs placés en tête de chaque script
    static let prelude = """
    on mkdate(y, m, d, s)
      set x to current date
      set day of x to 1
      set year of x to y
      set month of x to m
      set day of x to d
      set time of x to s
      return x
    end mkdate

    on esc(t)
      set t to t as text
      repeat with p in {{"&", "&amp;"}, {"<", "&lt;"}, {">", "&gt;"}}
        set AppleScript's text item delimiters to item 1 of p
        set parts to text items of t
        set AppleScript's text item delimiters to item 2 of p
        set t to parts as text
      end repeat
      set AppleScript's text item delimiters to ""
      return t
    end esc

    -- Résout une note : par son dossier si on le connaît (rapide), sinon au niveau de l'app
    on getNote(nid, fid)
      tell application "Notes"
        if fid is not "" then
          try
            set n to note id nid of folder id fid
            get id of n
            return n
          end try
        end if
        set n to note id nid
        get id of n
        return n
      end tell
    end getNote

    -- Tous les dossiers d'un compte en 3 événements : {{id, nom, id du parent ou ""}, …}
    -- (« folders of account » renvoie aussi les sous-dossiers, à plat)
    on tree(c)
      tell application "Notes"
        set i to id of folders of c
        set n to name of folders of c
        set p to id of container of folders of c
        set res to {}
        repeat with k from 1 to count of i
          set pid to item k of p
          if pid contains "/ICAccount/" then set pid to ""
          set end of res to {item k of i, item k of n, pid}
        end repeat
        return res
      end tell
    end tree

    -- Ids d'un dossier et de ses descendants, du parent vers les enfants
    on subtree(fl, root)
      set sel to {root}
      set changed to true
      repeat while changed
        set changed to false
        repeat with x in fl
          if (item 1 of x) is not in sel and (item 3 of x) is in sel then
            set end of sel to item 1 of x
            set changed to true
          end if
        end repeat
      end repeat
      return sel
    end subtree

    -- Nom d'un dossier dans l'arbre
    on nameOf(fl, fid)
      repeat with x in fl
        if item 1 of x is fid then return item 2 of x
      end repeat
      return ""
    end nameOf

    """

    /// Exécute un script (corps placé dans `tell application "Notes"`) sur le thread principal
    static func run(_ body: String, timeout: Int = 120) throws -> Any {
        let src = prelude + "with timeout of \(timeout) seconds\ntell application \"Notes\"\n" + body + "\nend tell\nend timeout\n"
        var result: Result<Any, Error> = .failure(MCPError("script not executed"))
        let work = {
            var err: NSDictionary?
            guard let script = NSAppleScript(source: src) else { result = .failure(MCPError("invalid script")); return }
            let d = script.executeAndReturnError(&err)
            if let err {
                let num = err[NSAppleScript.errorNumber] as? Int ?? 0
                let msg = err[NSAppleScript.errorMessage] as? String ?? "AppleScript error"
                if num == -1743 {
                    result = .failure(MCPError("macOS refuses control of Notes: allow it in System Settings > Privacy & Security > Automation (-1743)"))
                } else {
                    result = .failure(MCPError("\(msg) (\(num))"))
                }
                return
            }
            result = .success(value(d))
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync(execute: work) }
        return try result.get()
    }

    /// Littéral de chaîne AppleScript
    static func q(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
    static func list(_ a: [String]) -> String { "{" + a.map(q).joined(separator: ", ") + "}" }

    /// Date AppleScript construite sans dépendre de la langue du système
    static func date(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: d)
        return "(my mkdate(\(c.year!), \(c.month!), \(c.day!), \(c.hour! * 3600 + c.minute! * 60)))"
    }

    // MARK: - Conversion des résultats

    private static func fcc(_ s: String) -> DescType { s.utf8.reduce(0) { ($0 << 8) | DescType($1) } }
    private static let tList = fcc("list"), tTrue = fcc("true"), tFalse = fcc("fals"), tBool = fcc("bool"),
                        tLong = fcc("long"), tShort = fcc("shor"), tDouble = fcc("doub"), tDate = fcc("ldt "),
                        tNull = fcc("null"), tType = fcc("type"), tEnum = fcc("enum")

    static func value(_ d: NSAppleEventDescriptor) -> Any {
        switch d.descriptorType {
        case tList:
            return d.numberOfItems == 0 ? [Any]() : (1...d.numberOfItems).map { value(d.atIndex($0)!) }
        case tTrue: return true
        case tFalse: return false
        case tBool: return d.booleanValue
        case tLong, tShort: return Int(d.int32Value)
        case tDouble: return d.doubleValue
        case tDate: return d.dateValue ?? NSNull()
        case tNull, tType, tEnum: return d.stringValue ?? NSNull()
        default: return d.stringValue ?? NSNull()
        }
    }
}

/// Identifiants courts : x-coredata://<magasin>/ICNote/p123 ↔ n123 (ICFolder d, ICAttachment a, ICAccount c)
enum IDs {
    private static let entities = ["ICNote": "n", "ICFolder": "d", "ICAttachment": "a", "ICAccount": "c"]
    private static let lock = NSLock()
    private(set) static var store: String?

    static func short(_ full: String) -> String {
        let p = full.components(separatedBy: "/")  // ["x-coredata:", "", store, entity, pN]
        guard p.count == 5, p[0] == "x-coredata:", let pre = entities[p[3]], p[4].hasPrefix("p") else { return full }
        lock.lock(); if store == nil { store = p[2] }; let same = store == p[2]; lock.unlock()
        return same ? pre + p[4].dropFirst() : full
    }
    static func shorts(_ a: Any?) -> [String] { (a as? [Any] ?? []).compactMap { $0 as? String }.map(short) }

    static func full(_ s: String) throws -> String {
        let s = s.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("x-coredata://") { return s }
        guard let pre = s.first, let ent = entities.first(where: { $0.value == String(pre) })?.key,
              s.count > 1, s.dropFirst().allSatisfy(\.isNumber) else { throw MCPError("invalid id: \(s)") }
        if store == nil { _ = short(try AS.run("return id of default account") as? String ?? "") }
        guard let st = store else { throw MCPError("Notes store not found") }
        return "x-coredata://\(st)/\(ent)/p\(s.dropFirst())"
    }

    /// Numéro de ligne dans NoteStore.sqlite (Z_PK)
    static func pk(_ s: String) -> Int? {
        if let n = Int(s.dropFirst()), !s.hasPrefix("x-") { return n }
        return s.components(separatedBy: "/p").last.flatMap { Int($0) }
    }
}
