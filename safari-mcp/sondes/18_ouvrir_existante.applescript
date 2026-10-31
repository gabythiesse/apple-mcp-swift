-- Sonde 18 : reproduire le blocage de « ouvrir » dans une fenêtre existante (fenêtre de test about:blank)
with timeout of 8 seconds
tell application "Safari"
  set avant to id of every window
  make new document with properties {URL:"about:blank"}
  delay 1
  set W to 0
  set apres to id of every window
  repeat with k from 1 to count of apres
    if avant does not contain (item k of apres) then set W to (item k of apres)
  end repeat
  set log_ to {"W=" & W}
  set idx to {}
  try
    tell window id W
      set t to make new tab at end of tabs with properties {URL:"about:blank"}
      set end of log_ to "make ok"
      set end of idx to index of t
      set end of log_ to "index ok " & (item 1 of idx)
      set current tab to tab (item 1 of idx)
      set end of log_ to "current ok"
    end tell
  on error m
    set end of log_ to "ERREUR " & m
  end try
  close window id W
  return log_
end tell
end timeout
