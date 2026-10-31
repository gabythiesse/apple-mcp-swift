// Sonde 21 : coût du parcours récursif des dossiers (aucun nom affiché : comptes et durées seulement)
show("folders of account (racine)", runAS("tell application \"Notes\" to return (count of folders of default account) as string"))
show("ids racine en lot", runAS("tell application \"Notes\" to return (count of (id of folders of default account)) as string"))
show("walk récursif par références", runAS("""
on walk(c)
  tell application "Notes"
    set n to 0
    set fs to folders of c
    repeat with k from 1 to count of fs
      set n to n + 1 + my walk(item k of fs)
    end repeat
    return n
  end tell
end walk
tell application "Notes" to return (my walk(default account)) as string
""", timeout: 60))
show("walk récursif par ids", runAS("""
on walk(c)
  tell application "Notes"
    set n to 0
    repeat with fid in (id of folders of c)
      set n to n + 1 + my walk(folder id (contents of fid))
    end repeat
    return n
  end tell
end walk
tell application "Notes" to return (my walk(default account)) as string
""", timeout: 60))
