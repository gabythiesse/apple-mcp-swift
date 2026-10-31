-- Sonde 11 : PJ enregistrée sur disque, copie (duplicate), signature de test, renommage de boîte, suppression d'un message de test
tell application "Mail"
	set T to "MCP-TEST-$2"
	set out to ""
	set m to first message of mailbox T whose id is $1
	try
		set a to mail attachment 1 of m
		set out to out & "pj: " & (name of a) & " | " & (MIME type of a) & " | " & (file size of a) & " o | téléchargée " & (downloaded of a) & " | id " & (id of a) & linefeed
	on error e
		set out to out & "pj lecture ERR " & e & linefeed
	end try
	try
		save (mail attachment 1 of m) in (POSIX file "$3/sortie.txt")
		set out to out & "pj enregistrée" & linefeed
	on error e number n
		set out to out & "pj save ERR " & n & " " & e & linefeed
	end try
	try
		duplicate m to mailbox (T & "/[mcp-test] sous")
		delay 1
		set out to out & "copie: sous contient " & (count of messages of mailbox (T & "/[mcp-test] sous")) & linefeed
	on error e number n
		set out to out & "copie ERR " & n & " " & e & linefeed
	end try
	try
		make new signature with properties {name:"[mcp-test] sig $2", content:"Signature de test mcp"}
		set out to out & "signature créée: " & (exists signature ("[mcp-test] sig $2")) & linefeed
		set om to make new outgoing message with properties {subject:"[mcp-test] sig $2", content:"x", visible:false}
		set message signature of om to signature ("[mcp-test] sig $2")
		set out to out & "signature posée: " & (name of message signature of om) & linefeed
		close om saving no
	on error e number n
		set out to out & "signature ERR " & n & " " & e & linefeed
	end try
	try
		delete signature ("[mcp-test] sig $2")
	end try
	set out to out & "signature restante: " & (exists signature ("[mcp-test] sig $2")) & linefeed
	try
		set name of mailbox (T & "/[mcp-test] sous") to "[mcp-test] renommée"
		set out to out & "renommée: " & (exists mailbox (T & "/[mcp-test] renommée")) & linefeed
	on error e number n
		set out to out & "renommage ERR " & n & " " & e & linefeed
	end try
	return out
end tell
