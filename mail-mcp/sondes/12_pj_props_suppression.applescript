-- Sonde 12 : propriétés de PJ une par une ; suppression d'un message de test (où va-t-il ?)
tell application "Mail"
	set T to "MCP-TEST-$2"
	set out to ""
	set m to first message of mailbox T whose id is $1
	set a to mail attachment 1 of m
	repeat with p in {"name", "MIME type", "file size", "downloaded", "id"}
		try
			if p as text is "name" then set v to name of a
			if p as text is "MIME type" then set v to MIME type of a
			if p as text is "file size" then set v to file size of a
			if p as text is "downloaded" then set v to downloaded of a
			if p as text is "id" then set v to id of a
			set out to out & p & "=" & v & " ; "
		on error e
			set out to out & p & "=ERR ; "
		end try
	end repeat
	set out to out & linefeed
	set c to first message of mailbox (T & "/[mcp-test] renommée") whose subject contains "pj conteneur"
	set cid to id of c
	delete c
	delay 2
	set out to out & "supprimé " & cid & " | restant dans la boîte: " & (count of (messages of mailbox (T & "/[mcp-test] renommée") whose id is cid))
	return out
end tell
