// Sonde 16 : où est la note du dossier « déplacé » (supprimé) ? Lecture seule, filtrée sur le nom marqué
show("note de sous2", runAS("""
tell application "Notes"
  set out to ""
  repeat with n in (notes whose name starts with "[mcp-test] dans sous2")
    set c to container of n
    set out to out & (id of n) & " | " & (name of c) & linefeed
  end repeat
  return "trouvées: " & out
end tell
"""))
