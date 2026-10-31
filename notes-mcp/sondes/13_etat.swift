// Sonde 13 : état des objets de test (filtré sur les noms marqués MCP-TEST- / [mcp-test]) : ids, conteneurs
show("dossiers marqués", runAS("""
tell application "Notes"
  set out to ""
  repeat with fo in (folders whose name starts with "MCP-TEST-" or name starts with "[mcp-test]")
    set out to out & (id of fo) & " | " & (name of fo) & " | notes=" & (count of notes of fo) & " | sous=" & (count of folders of fo) & linefeed
  end repeat
  repeat with fo in folders of default account
    repeat with sfo in (folders of fo whose name starts with "[mcp-test]")
      set out to out & "  sous: " & (id of sfo) & " | " & (name of sfo) & " | parent=" & (name of fo) & linefeed
    end repeat
  end repeat
  return out
end tell
"""))
show("notes [mcp-test] simple/tag", runAS("""
tell application "Notes"
  set out to ""
  repeat with n in (notes whose name starts with "[mcp-test] simple" or name starts with "[mcp-test] tag")
    set c to container of n
    set out to out & (id of n) & " | " & (name of n) & " | " & (name of c) & linefeed
  end repeat
  return out
end tell
"""))
