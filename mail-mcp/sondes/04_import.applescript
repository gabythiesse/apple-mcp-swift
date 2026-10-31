-- Sonde 04 : import d'une boîte mbox de test (crée des messages locaux sans réseau)
tell application "Mail"
	set avant to name of every mailbox
	import Mail mailbox at (POSIX file "$1")
	delay 3
	set apres to name of every mailbox
	set out to ""
	repeat with n in apres
		if avant does not contain (n as text) then set out to out & "nouvelle racine: " & n & linefeed
	end repeat
	return out & "racines avant/après: " & (count of avant) & "/" & (count of apres)
end tell
