// Sonde 15 : « move folder » via AppleScript sur un sous-dossier neuf (avec une note) : que devient-il ?
let ids = try! String(contentsOfFile: "ids.txt", encoding: .utf8).split(separator: "\n").map(String.init)
let f = ids[0]
let r = runAS("""
tell application "Notes"
  set s2 to make new folder at folder id "\(f)" with properties {name:"[mcp-test] sous2"}
  make new note at s2 with properties {body:"[mcp-test] dans sous2"}
  return id of s2
end tell
""")
show("création sous2", r)
let s2 = r.0!
try! (ids + [s2]).joined(separator: "\n").write(toFile: "ids.txt", atomically: true, encoding: .utf8)
show("résolution avant", runAS("tell application \"Notes\" to return name of folder id \"\(s2)\""))
show("move → compte", runAS("tell application \"Notes\"\nset x to folder id \"\(s2)\"\nmove x to default account\nreturn \"ok\"\nend tell"))
show("résolution après", runAS("tell application \"Notes\" to return name of folder id \"\(s2)\""))
show("racine [mcp-test]", runAS("tell application \"Notes\" to return (count of (folders of default account whose name starts with \"[mcp-test]\")) as string"))
