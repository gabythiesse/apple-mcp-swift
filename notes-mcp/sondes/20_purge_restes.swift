// Sonde 20 : purge des notes [mcp-test] restées dans « Recently Deleted » (par id, nom marqué vérifié)
show("purge restes", runAS("""
tell application "Notes"
  set ids to id of (notes whose name starts with "[mcp-test]")
  repeat with x in ids
    set n to note id x
    if name of n starts with "[mcp-test]" then delete n
  end repeat
  return ((count of ids) as string) & " purgées ; restantes=" & (count of (notes whose name starts with "[mcp-test]"))
end tell
"""))
