-- Sonde 02 : voie AppleScript — version, comptes (types seulement, aucun nom), boîte locale de test + sous-boîte
tell application "Mail"
	set out to "version " & (application version) & linefeed
	set out to out & "comptes: " & (count of accounts) & " types: "
	repeat with a in accounts
		set out to out & (account type of a as text) & " "
	end repeat
	set out to out & linefeed & "existe déjà: " & (exists mailbox "$1") & linefeed
	if not (exists mailbox "$1") then make new mailbox with properties {name:"$1"}
	set mb to mailbox "$1"
	set out to out & "créée: " & (name of mb) & " | compte: " & ((account of mb) is missing value) & linefeed
	make new mailbox with properties {name:"$1/[mcp-test] sous"}
	set out to out & "enfants: " & (count of mailboxes of mb) & " | nom enfant: " & (name of mailbox 1 of mb) & linefeed
	set out to out & "par chemin: " & (exists mailbox "$1/[mcp-test] sous")
end tell
