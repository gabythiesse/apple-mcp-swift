// Sonde 27 : « id of container of notes » : valeurs manquantes ? ordre aligné sur « id of notes » ? (comptes seulement)
show("alignement", runAS("""
tell application "Notes"
  set ai to id of notes
  set ac to id of container of notes
  set manq to 0
  repeat with x in ac
    if contents of x is missing value then set manq to manq + 1
  end repeat
  set pos to 0
  repeat with k from 1 to count of ai
    if item k of ai ends with "/p1655" then set pos to k
  end repeat
  set v to "?"
  if pos > 0 then set v to item pos of ac
  set cc to container of note id "x-coredata://776CB633-AE08-4EDE-8F4F-3AF34F655A7F/ICNote/p1655"
  set c1 to id of cc
  return ((count of ai) as string) & " ids, " & (count of ac) & " conteneurs, manquants=" & manq & " | test: pos=" & pos & " lot=" & v & " direct=" & c1
end tell
"""))
