// Sonde 01 : la voie AppleScript marche dans le process ; comptes (noms = types), nombre total de notes (compte, pas de contenu)
show("comptes", runAS("""
tell application "Notes"
  set out to ""
  repeat with a in accounts
    set out to out & (name of a) & " | dossiers=" & (count of folders of a) & " | notes=" & (count of notes of a) & linefeed
  end repeat
  return out & "defaut=" & (name of default account)
end tell
"""))
