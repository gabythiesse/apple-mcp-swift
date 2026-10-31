-- Sonde 20 (nettoyage) : ramène les messages de test de la corbeille vers la boîte de test, par identifiant
tell application "Mail"
	set dest to mailbox "MCP-TEST-$1/[mcp-test] renommée"
	set icl to mailbox "Deleted Messages" of (first account whose id is "B438865A-FB87-4B00-A0FD-D4429B6DA08A")
	set loc to mailbox "Deleted Messages"
	set out to ""
	repeat with i in {8383, 8385, 8389}
		try
			move (first message of loc whose id is i) to dest
			set out to out & i & " ok, "
		on error e
			set out to out & i & " ERR " & e & ", "
		end try
	end repeat
	repeat with i in {8386, 8387, 8388, 8390}
		try
			move (first message of icl whose id is i) to dest
			set out to out & i & " ok, "
		on error e
			set out to out & i & " ERR " & e & ", "
		end try
	end repeat
	delay 2
	return out & linefeed & "dans la boîte de test: " & (count of messages of dest)
end tell
