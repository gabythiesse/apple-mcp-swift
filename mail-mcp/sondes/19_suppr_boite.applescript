-- Sonde 19 : formes alternatives de suppression d'une boîte locale de test
tell application "Mail"
	set out to "existe: " & (exists mailbox "MCP-TEST-$1") & linefeed
	try
		set sb to mailbox 1 of mailbox "MCP-TEST-$1"
		set out to out & "enfant: " & (name of sb) & linefeed
		delete sb
		set out to out & "A (élément de la boîte) OK" & linefeed
	on error e number n
		set out to out & "A ERR " & n & " " & e & linefeed
	end try
	try
		delete (first mailbox whose name is "MCP-TEST-$1")
		set out to out & "B (whose name) OK" & linefeed
	on error e number n
		set out to out & "B ERR " & n & " " & e & linefeed
	end try
	set out to out & "existe après: " & (exists mailbox "MCP-TEST-$1")
	return out
end tell
