-- Sonde 18 : effacement définitif d'un message de test en corbeille (deleted status) ; suppression de boîtes de test (enfant d'abord)
tell application "Mail"
	set out to ""
	try
		set m to first message of mailbox "Deleted Messages" of (first account whose id is "B438865A-FB87-4B00-A0FD-D4429B6DA08A") whose id is 8390
		set deleted status of m to true
		set out to out & "deleted status iCloud 8390: " & (deleted status of m) & linefeed
	on error e number n
		set out to out & "deleted status ERR " & n & " " & e & linefeed
	end try
	try
		delete mailbox "MCP-TEST-$1/[mcp-test] renommée"
		set out to out & "sous-boîte supprimée: " & (not (exists mailbox "MCP-TEST-$1/[mcp-test] renommée")) & linefeed
	on error e number n
		set out to out & "suppr sous-boîte ERR " & n & " " & e & linefeed
	end try
	try
		delete mailbox "MCP-TEST-$1"
		set out to out & "boîte supprimée: " & (not (exists mailbox "MCP-TEST-$1")) & linefeed
	on error e number n
		set out to out & "suppr boîte ERR " & n & " " & e & linefeed
	end try
	return out
end tell
