// Sonde 19 : coût de « note id X » (app vs dossier), des lectures par note et des variantes de suppression,
// sur 30 notes de test dans un dossier MCP-TEST dédié (tout supprimé et purgé à la fin, vérifié)
let ts = Int(Date().timeIntervalSince1970)
let r = runAS("""
tell application "Notes"
  set f to make new folder at default account with properties {name:"MCP-TEST-\(ts)"}
  repeat with i from 1 to 30
    make new note at f with properties {body:"<div><h1>[mcp-test] b" & i & "</h1></div><div>x</div>"}
  end repeat
  set AppleScript's text item delimiters to linefeed
  return ((id of f) & linefeed & ((id of notes of f) as text))
end tell
""")
show("creation 30", (r.0.map { String($0.prefix(80)) }, r.1, r.2))
let l = r.0!.split(separator: "\n").map(String.init); let f = l[0]; let ids = Array(l.dropFirst())
func lst(_ a: ArraySlice<String>) -> String { "{" + a.map { "\"\($0)\"" }.joined(separator: ",") + "}" }
show("nom via note id (app) x5", runAS("tell application \"Notes\"\nset out to {}\nrepeat with x in \(lst(ids[0..<5]))\nset end of out to name of note id x\nend repeat\nreturn count of out\nend tell"))
show("nom via note id of folder x5", runAS("tell application \"Notes\"\nset f to folder id \"\(f)\"\nset out to {}\nrepeat with x in \(lst(ids[5..<10]))\nset end of out to name of note id x of f\nend repeat\nreturn count of out\nend tell"))
show("body via note id (app) x5", runAS("tell application \"Notes\"\nset out to {}\nrepeat with x in \(lst(ids[0..<5]))\nset end of out to body of note id x\nend repeat\nreturn count of out\nend tell"))
show("delete note id (app) x5", runAS("tell application \"Notes\"\nrepeat with x in \(lst(ids[0..<5]))\ndelete note id x\nend repeat\nreturn 5\nend tell"))
show("delete note id of folder x5", runAS("tell application \"Notes\"\nset f to folder id \"\(f)\"\nrepeat with x in \(lst(ids[5..<10]))\ndelete note id x of f\nend repeat\nreturn 5\nend tell"))
show("delete liste de refs x5", runAS("tell application \"Notes\"\nset rs to {}\nrepeat with x in \(lst(ids[10..<15]))\nset end of rs to note id x\nend repeat\ndelete rs\nreturn 5\nend tell"))
show("purge (2e delete) x15", runAS("tell application \"Notes\"\nrepeat with x in \(lst(ids[0..<15]))\ntry\ndelete note id x\nend try\nend repeat\nreturn 15\nend tell"))
show("delete dossier (15 notes dedans)", runAS("tell application \"Notes\"\ndelete folder id \"\(f)\"\nreturn 1\nend tell"))
show("état des 15 notes du dossier supprimé", runAS("tell application \"Notes\"\nset out to \"\"\nrepeat with x in \(lst(ids[15..<30]))\ntry\nset n to note id x\nset c to container of n\nset out to name of c\nend try\nend repeat\nreturn \"conteneur: \" & out\nend tell"))
show("purge des 15 + vérif", runAS("tell application \"Notes\"\nrepeat with x in \(lst(ids[15..<30]))\ntry\ndelete note id x\nend try\nend repeat\nreturn ((count of (notes whose name starts with \"[mcp-test]\")) as string) & \"/\" & (count of (folders whose name starts with \"MCP-TEST-\"))\nend tell"))
