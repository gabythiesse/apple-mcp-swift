// Nettoyage : supprime par id toutes les notes de test (dossier MCP-TEST- de ids.txt + ids passés en argument),
// deux fois (corbeille puis purge de « Recently Deleted »), puis les sous-dossiers et le dossier.
// Refuse tout objet dont le nom n'est pas marqué. Vérifie qu'il ne reste rien de marqué, corbeille comprise.
let ids = try! String(contentsOfFile: "ids.txt", encoding: .utf8).split(separator: "\n").map(String.init)
let extra = CommandLine.arguments.dropFirst().map { "\"\($0)\"" }.joined(separator: ", ")
show("nettoyage", runAS("""
tell application "Notes"
  set f to folder id "\(ids[0])"
  if name of f does not start with "MCP-TEST-" then error "refus dossier " & name of f
  set nids to (id of notes of f) & {\(extra)}
  repeat with sfo in folders of f
    try
      set nids to nids & (id of notes of sfo)
    end try
  end repeat
  set traitees to 0
  repeat 2 times
    repeat with nid in nids
      try
        set n to note id nid
        if name of n starts with "[mcp-test]" then
          delete n
          set traitees to traitees + 1
        end if
      end try
    end repeat
  end repeat
  repeat with sfo in folders of f
    try
      if name of sfo starts with "[mcp-test]" then delete sfo
    end try
  end repeat
  delete f
  set restantes to 0
  repeat with nid in nids
    try
      note id nid
      set restantes to restantes + 1
    end try
  end repeat
  return "ids=" & (count of nids) & " suppressions=" & traitees & " restantes=" & restantes & " | marquées restantes partout (corbeille comprise)=" & (count of (notes whose name starts with "[mcp-test]")) & " | dossiers MCP-TEST=" & (count of (folders whose name starts with "MCP-TEST-"))
end tell
""", timeout: 400))
