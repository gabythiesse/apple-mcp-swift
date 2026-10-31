-- Supprime une boîte de TEST (préfixe MCP-TEST- obligatoire) par le menu de Mail : AppleScript ne sait pas supprimer une boîte (sonde 19).
-- Vérifie la sélection, puis le texte de la feuille de confirmation, avant de cliquer. Usage : osascript supprimer_boite_test.applescript "<chemin>" confirmer
on run argv
	set chemin to item 1 of argv
	if chemin does not start with "MCP-TEST-" then error "refused: not a test mailbox"
	tell application "Mail"
		activate
		set mv to message viewer 1
		set selected mailboxes of mv to {mailbox chemin}
		delay 1
		set sel to selected mailboxes of mv
		if (count of sel) is not 1 then error "unexpected selection: " & (count of sel)
		set nom to name of item 1 of sel
		set nb to count of messages of item 1 of sel
	end tell
	set attendu to last item of my decoupe(chemin)
	if nom is not attendu then error "unexpected selection: " & nom
	tell application "System Events" to tell process "Mail"
		set frontmost to true
		click menu item "Supprimer la boîte aux lettres…" of menu 1 of menu bar item "Boîte aux lettres" of menu bar 1
		delay 1
		set w to window 1
		set btns to {}
		if (count of sheets of w) > 0 then
			set btns to name of every button of sheet 1 of w
			set txt to value of every static text of sheet 1 of w
		else
			set txt to "no sheet; windows: " & (name of every window as text)
		end if
		if item 2 of argv is "confirmer" and (count of sheets of w) > 0 then
			if (item 1 of txt) does not contain nom then error "refused, unexpected sheet: " & (item 1 of txt)
			click button "Supprimer" of sheet 1 of w
			return "selected " & nom & " (" & nb & " messages) → Delete clicked"
		end if
		return {"selection", nom, nb, "buttons", btns, "text", txt}
	end tell
end run
on decoupe(s)
	set AppleScript's text item delimiters to "/"
	set r to text items of s
	set AppleScript's text item delimiters to ""
	return r
end decoupe
