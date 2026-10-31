// Sonde 09 : d'où vient ~1 s par note créée ? Variantes sur 5 notes chacune, dans le dossier de test.
let f = try! String(contentsOfFile: "ids.txt", encoding: .utf8).split(separator: "\n").map(String.init)[0]
func lot(_ label: String, _ props: String) {
  show(label, runAS("""
  tell application "Notes"
    set f to folder id "\(f)"
    repeat with i from 1 to 5
      make new note at f with properties \(props)
    end repeat
    return "5"
  end tell
  """))
}
lot("body texte court", "{body:\"[mcp-test] court \" & i}")
lot("body h1+div", "{body:\"<div><h1>[mcp-test] h1 \" & i & \"</h1></div><div>x</div>\"}")
lot("name seul", "{name:\"[mcp-test] nom \" & i}")
lot("body texte court (2e passe)", "{body:\"[mcp-test] court bis \" & i}")
show("1 note", runAS("tell application \"Notes\" to return id of (make new note at folder id \"\(f)\" with properties {body:\"[mcp-test] une\"})"))
show("20 notes avec id renvoyé", runAS("""
tell application "Notes"
  set f to folder id "\(f)"
  set out to {}
  repeat with i from 1 to 20
    set end of out to id of (make new note at f with properties {body:"<div><h1>[mcp-test] ids " & i & "</h1></div><div>x</div>"})
  end repeat
  return (count of out) as string
end tell
"""))
