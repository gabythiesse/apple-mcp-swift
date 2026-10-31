-- Sonde 16 : indésirable sur un message de test, sélection (nombre seulement), relève du courrier
tell application "Mail"
	set m to first message of mailbox "MCP-TEST-$2" whose id is $1
	set junk mail status of m to true
	set j to junk mail status of m
	set junk mail status of m to false
	set out to "indésirable posé/retiré: " & j & "/" & (junk mail status of m) & linefeed
	try
		set out to out & "visionneuses: " & (count of message viewers) & " | sélection: " & (count of (selection as list)) & linefeed
	on error e
		set out to out & "sélection ERR " & e & linefeed
	end try
	check for new mail
	set out to out & "relève lancée" & linefeed
	return out
end tell
