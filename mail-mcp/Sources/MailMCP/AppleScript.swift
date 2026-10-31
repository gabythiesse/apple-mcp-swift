// Voie AppleScript : NSAppleScript dans le processus (un script par appel d'outil, qui traite tout le lot)
import Foundation

enum AS {
    /// Littéral AppleScript sûr pour une chaîne quelconque
    static func q(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Exécute un corps de script dans `tell application "Mail"`. `avant` contient des gestionnaires hors du tell.
    @discardableResult
    static func run(_ body: String, avant: String = "") throws -> Any {
        // Plafond de 30 s : sans lui, un script bloqué attend 2 min l'expiration par défaut des Apple Events
        try runRaw(avant + "\ntell application \"Mail\"\nwith timeout of 30 seconds\n" + body + "\nend timeout\nend tell")
    }

    static func runRaw(_ src: String) throws -> Any {
        var out: Any = NSNull()
        var errMsg: String?
        var errNum = 0
        let work = {
            var err: NSDictionary?
            guard let script = NSAppleScript(source: src) else { errMsg = "invalid script"; return }
            let d = script.executeAndReturnError(&err)
            if let e = err {
                errNum = (e[NSAppleScript.errorNumber] as? Int) ?? 0
                errMsg = (e[NSAppleScript.errorMessage] as? String) ?? "AppleScript error"
                return
            }
            out = convert(d)
        }
        // NSAppleScript n'est pas sûr hors du thread principal
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync(execute: work) }
        if let m = errMsg {
            if errNum == -1743 || errNum == -1744 {
                throw MCPError("Automation denied: System Settings > Privacy & Security > Automation > AppleMCP > turn on Mail and System Events (check all: ./installer.command --check).")
            }
            throw MCPError("Mail : \(m) (\(errNum))")
        }
        return out
    }

    private static func code(_ s: String) -> FourCharCode { s.utf8.reduce(0) { ($0 << 8) | FourCharCode($1) } }
    private static let tList = code("list"), tTrue = code("true"), tFalse = code("fals"), tBool = code("bool"),
        tLong = code("long"), tShort = code("shor"), tComp = code("comp"), tDouble = code("doub"), tSingle = code("sing"),
        tType = code("type"), tMissing = code("msng"), tDate = code("ldt "), tNull = code("null")

    /// Descripteur Apple Event → valeur Swift (listes, texte, nombres, booléens, dates, missing value)
    static func convert(_ d: NSAppleEventDescriptor) -> Any {
        switch d.descriptorType {
        case tList: return d.numberOfItems == 0 ? [Any]() : (1...d.numberOfItems).map { convert(d.atIndex($0)!) }
        case tTrue: return true
        case tFalse: return false
        case tBool: return d.booleanValue
        case tLong, tShort: return Int(d.int32Value)
        case tComp, tDouble, tSingle: return d.doubleValue
        case tDate: return d.dateValue ?? NSNull()
        case tNull: return NSNull()
        case tType: return d.typeCodeValue == tMissing ? NSNull() : (d.stringValue ?? NSNull())
        default: return d.stringValue ?? NSNull()
        }
    }
}

// Accès typé aux résultats AppleScript
extension Array where Element == Any {
    func s(_ i: Int) -> String { i < count ? (self[i] as? String ?? "") : "" }
    func n(_ i: Int) -> Int { i < count ? ((self[i] as? Int) ?? Int((self[i] as? Double) ?? 0)) : 0 }
    func l(_ i: Int) -> [Any] { i < count ? (self[i] as? [Any] ?? []) : [] }
    func b(_ i: Int) -> Bool { i < count ? (self[i] as? Bool ?? false) : false }
}
