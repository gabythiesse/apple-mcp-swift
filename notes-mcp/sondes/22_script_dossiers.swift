// Sonde 22 : le script exact de l'outil dossiers, exécuté hors serveur (aucun nom affiché : nombre d'entrées)
show("defaut folder", runAS("tell application \"Notes\" to return id of default folder of default account", timeout: 30))
show("walk + count notes", runAS("""
on walk(c, pid)
  tell application "Notes"
    set res to {}
    set fs to folders of c
    repeat with k from 1 to count of fs
      set fo to item k of fs
      set fid to id of fo
      set end of res to {fo, fid, name of fo, pid}
      set res to res & my walk(fo, fid)
    end repeat
    return res
  end tell
end walk
with timeout of 30 seconds
tell application "Notes"
  set fl to my walk(default account, "")
  set rows to {}
  repeat with k from 1 to count of fl
    set x to item k of fl
    set end of rows to {item 2 of x, count of notes of (item 1 of x)}
  end repeat
  return (count of rows) as string
end tell
end timeout
""", timeout: 60))
