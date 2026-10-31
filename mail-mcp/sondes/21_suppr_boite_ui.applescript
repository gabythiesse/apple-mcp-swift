-- Sonde 21 (nettoyage) : suppression d'une boîte de test par le menu de Mail, après vérification stricte de la sélection
-- arg 1 = chemin de la boîte de test ; arg 2 = "voir" (ouvre la confirmation et liste ses boutons) ou "confirmer"
on run argv
	set chemin to item 1 of argv
	if chemin does not start with "MCP-TEST-" then error "refus : pas une boîte de test"
	tell application "Mail"
		activate
		set mv to message viewer 1
		set selected mailboxes of mv to {mailbox chemin}
		delay 1
		set sel to selected mailboxes of mv
		if (count of sel) is not 1 then error "sélection inattendue: " & (count of sel)
		set nom to name of item 1 of sel
		set nb to count of messages of item 1 of sel
	end tell
	set attendu to last item of my decoupe(chemin)
	if nom is not attendu then error "sélection inattendue: " & nom
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
			set txt to "pas de feuille ; fenêtres: " & (name of every window as text)
		end if
		if item 2 of argv is "confirmer" and (count of sheets of w) > 0 then
			if (item 1 of txt) does not contain nom then error "refus, feuille inattendue: " & (item 1 of txt)
			click button "Supprimer" of sheet 1 of w
			return "sélection " & nom & " (" & nb & " messages) → Supprimer cliqué"
		end if
		return {"sélection", nom, nb, "boutons", btns, "texte", txt}
	end tell
end run
on decoupe(s)
	set AppleScript's text item delimiters to "/"
	set r to text items of s
	set AppleScript's text item delimiters to ""
	return r
end decoupe
